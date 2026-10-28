import Foundation
import Contacts
import UseCases

// Admission is synchronous on the notification producer, including while the
// Contacts actor is occupied by a fetch. UI tasks cannot revive an older scope.
private final class DiallerContactsAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    private var suspended = false
    func ticket() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func invalidate() { lock.lock(); value &+= 1; lock.unlock() }
    func setSuspended(_ suspended: Bool) { lock.lock(); value &+= 1; self.suspended = suspended; lock.unlock() }
    func isCurrent(_ ticket: UInt64) -> Bool { lock.lock(); defer { lock.unlock() }; return !suspended && ticket == value }
}

@objc final class JPSDiallerContactDestination: NSObject {
    @objc let address: String
    @objc let label: String
    @objc let isSIPEmail: Bool
    init(address: String, label: String, isSIPEmail: Bool) {
        self.address = address; self.label = label; self.isSIPEmail = isSIPEmail
    }
}

@objc final class JPSDiallerContactMatch: NSObject {
    @objc let displayName: String
    @objc let destinations: [JPSDiallerContactDestination]
    let ticket: UInt64
    init(displayName: String, destinations: [JPSDiallerContactDestination], ticket: UInt64) {
        self.displayName = displayName; self.destinations = destinations; self.ticket = ticket
    }
}

@MainActor
@objc final class JPSDiallerContacts: NSObject {
    nonisolated private let admission = DiallerContactsAdmission()
    private var snapshot: (ticket: UInt64, value: ContactCompletionSnapshot)?
    private let authorization: () -> Bool

    // No directory, defaults or permission operation is performed by this value
    // boundary. Production supplies only the current non-prompting access check.
    init(snapshot: ContactCompletionSnapshot? = nil, authorization: @escaping () -> Bool = { false }) {
        self.authorization = authorization
        super.init()
        if let snapshot { self.snapshot = (admission.ticket(), snapshot) }
    }

    nonisolated func currentTicket() -> UInt64 { admission.ticket() }

    @objc nonisolated func invalidate() {
        admission.invalidate()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let snapshot, !admission.isCurrent(snapshot.ticket) { self.snapshot = nil }
        }
    }

    func setSuspended(_ suspended: Bool) {
        admission.setSuspended(suspended)
        snapshot = nil
    }

    @discardableResult
    nonisolated func enqueue(_ ticket: UInt64, snapshot: ContactCompletionSnapshot?) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self, admission.isCurrent(ticket) else { return }
            self.snapshot = snapshot.map { (ticket, $0) }
        }
    }

    private func availableSnapshot() -> (ticket: UInt64, value: ContactCompletionSnapshot)? {
        guard let snapshot else { return nil }
        guard isAvailable(snapshot.ticket) else { return nil }
        return snapshot
    }

    private func isAvailable(_ ticket: UInt64) -> Bool {
        guard admission.isCurrent(ticket) else {
            if let snapshot, !admission.isCurrent(snapshot.ticket) { self.snapshot = nil }
            return false
        }
        guard authorization() else { invalidate(); snapshot = nil; return false }
        return true
    }

    @objc(completionsForSubstring:)
    func completions(for substring: String) -> [String] {
        guard let snapshot = availableSnapshot() else { return [] }
        let result = snapshot.value.completionStrings(for: substring)
        return isAvailable(snapshot.ticket) ? result : []
    }

    @objc(firstContactMatchingUser:SIPAddress:displayName:)
    func firstContact(matchingUser user: String, sipAddress: String, displayName: String) -> JPSDiallerContactMatch? {
        guard let snapshot = availableSnapshot(),
              let contact = snapshot.value.firstContact(user: user, sipAddress: sipAddress, displayName: displayName),
              let metadata = contact.completionMetadata else { return nil }
        var destinations = contact.phones.map {
            JPSDiallerContactDestination(address: $0.number, label: phoneLabel(raw: $0.rawLabel, fallback: $0.label), isSIPEmail: false)
        }
        destinations += contact.emails.filter { $0.rawLabel?.caseInsensitiveCompare("sip") == .orderedSame }.map {
            JPSDiallerContactDestination(address: $0.address, label: phoneLabel(raw: "sip", fallback: $0.label), isSIPEmail: true)
        }
        guard isAvailable(snapshot.ticket) else { return nil }
        return JPSDiallerContactMatch(displayName: metadata.displayName, destinations: destinations, ticket: snapshot.ticket)
    }

    @objc(isCurrentMatch:)
    func isCurrent(_ match: JPSDiallerContactMatch) -> Bool {
        isAvailable(match.ticket)
    }
}

// Preserve Telephone's existing label table for the token menu. Other labels
// already carry the Contacts adapter's localized display value; no store lookup
// is involved in either path.
private func phoneLabel(raw: String?, fallback: String) -> String {
    let key: String
    switch raw {
    case CNLabelWork: key = "work"
    case CNLabelHome: key = "home"
    case CNLabelPhoneNumberMobile: key = "mobile"
    case CNLabelPhoneNumberMain: key = "main"
    case CNLabelPhoneNumberHomeFax: key = "home fax"
    case CNLabelPhoneNumberWorkFax: key = "work fax"
    case CNLabelPhoneNumberPager: key = "pager"
    case CNLabelOther: key = "other"
    case "sip": key = "sip"
    default: return fallback
    }
    return NSLocalizedString(key, tableName: "AddressBookLabels", comment: "Call destination label.")
}
