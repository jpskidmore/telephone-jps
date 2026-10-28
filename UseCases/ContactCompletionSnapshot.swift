import Foundation

/// A complete immutable directory for synchronous token-field callbacks. Building
/// it performs no directory access; production builds it during the matching
/// index's existing ContactsActor enumeration.
public struct ContactCompletionSnapshot: Sendable {
    public let contacts: [Contact]
    private let entries: [Entry]

    public init(contacts: [Contact]) {
        self.contacts = contacts
        entries = contacts.compactMap(Entry.init)
    }

    /// Keeps source order, duplicate destinations, native NSString comparisons
    /// and the two established completion forms. There is no result-count cap.
    public func completionStrings(for substring: String) -> [String] {
        guard !substring.isEmpty else { return [] }
        var result: [String] = []
        let components = nameSplits(substring)
        for entry in entries {
            for address in entry.phones where prefix(address.value, substring, insensitive: false) {
                result.append(address.addressCompletion)
            }
            for address in entry.sipEmails where prefix(address.value, substring, insensitive: true) {
                result.append(address.addressCompletion)
            }
            let name: String?
            if entry.metadata.isCompany {
                name = prefix(entry.organisation, substring, insensitive: true) && !entry.metadata.organisation.isEmpty
                    ? entry.metadata.organisation : nil
            } else if prefix(entry.givenName, substring, insensitive: true) ||
                        prefix(entry.familyName, substring, insensitive: true) ||
                        prefix(entry.givenNameFirst, substring, insensitive: true) ||
                        prefix(entry.familyNameFirst, substring, insensitive: true) {
                // The old delegate first admitted records through a compound
                // name/address predicate, then checked rendered-name prefixes.
                // Those are not equivalent for leading/repeated whitespace.
                // Keep both stages, including ordinary-email admission even
                // though only SIP-labelled emails become call destinations.
                let admittedByName = prefix(entry.givenName, substring, insensitive: true) ||
                    prefix(entry.familyName, substring, insensitive: true) || components.contains {
                        (equal(entry.givenName, $0.0) && ($0.1.isEmpty || prefix(entry.familyName, $0.1, insensitive: true))) ||
                        (equal(entry.familyName, $0.0) && ($0.1.isEmpty || prefix(entry.givenName, $0.1, insensitive: true)))
                    }
                let admittedByAddress = admittedByName ? false :
                    entry.phones.contains { prefix($0.value, substring, insensitive: false) } ||
                    entry.allEmails.contains { prefix($0, substring, insensitive: true) }
                guard admittedByName || admittedByAddress else { continue }
                if !entry.metadata.givenName.isEmpty && !entry.metadata.familyName.isEmpty {
                    name = prefix(entry.givenNameFirst, substring, insensitive: true)
                        ? entry.givenNameFirst as String : entry.familyNameFirst as String
                } else if !entry.metadata.givenName.isEmpty {
                    name = entry.metadata.givenName
                } else if !entry.metadata.familyName.isEmpty {
                    name = entry.metadata.familyName
                } else {
                    name = nil
                }
            } else {
                name = nil
            }
            if let name {
                for address in entry.phones { result.append("\(name) <\(address.value)>") }
                for address in entry.sipEmails { result.append("\(name) <\(address.value)>") }
            }
        }
        if let first = result.first, prefix(first as NSString, substring, insensitive: true) {
            result[0] = (first as NSString).replacingCharacters(in: NSRange(location: 0, length: (substring as NSString).length), with: substring)
        }
        return result
    }

    /// An unnamed raw token deliberately searches phones only, as the legacy
    /// callback does. Named tokens may locate a record through any email label;
    /// the caller then exposes only its SIP-labelled emails as destinations.
    public func firstContact(user: String, sipAddress: String, displayName: String) -> Contact? {
        let components = nameSplits(displayName)
        for entry in entries {
            let phoneMatches = entry.contact.phones.contains { ($0.number as NSString).isEqual(to: user) }
            if displayName.isEmpty {
                if phoneMatches { return entry.contact }
                continue
            }
            let addressMatches = phoneMatches || entry.contact.emails.contains {
                ($0.address as NSString).caseInsensitiveCompare(sipAddress) == .orderedSame
            }
            guard addressMatches else { continue }
            if equal(entry.givenName, displayName) || equal(entry.familyName, displayName) ||
                equal(entry.organisation, displayName) || components.contains(where: {
                    (equal(entry.givenName, $0.0) && equal(entry.familyName, $0.1)) ||
                    (equal(entry.givenName, $0.1) && equal(entry.familyName, $0.0))
                }) {
                return entry.contact
            }
        }
        return nil
    }
}

private extension ContactCompletionSnapshot {
    struct Address: @unchecked Sendable {
        let value: NSString
        let addressCompletion: String
        init(_ value: String, name: String) {
            self.value = value as NSString
            addressCompletion = name.isEmpty ? value : "\(value) (\(name))"
        }
    }

    // NSString values are immutable copies created from Swift Strings and never
    // exposed. Foundation's native comparisons preserve the delegate's rules.
    struct Entry: @unchecked Sendable {
        let contact: Contact
        let metadata: Contact.CompletionMetadata
        let givenName: NSString
        let familyName: NSString
        let organisation: NSString
        let givenNameFirst: NSString
        let familyNameFirst: NSString
        let phones: [Address]
        let sipEmails: [Address]
        let allEmails: [NSString]

        init?(_ contact: Contact) {
            guard let metadata = contact.completionMetadata else { return nil }
            self.contact = contact
            self.metadata = metadata
            givenName = metadata.givenName as NSString
            familyName = metadata.familyName as NSString
            organisation = metadata.organisation as NSString
            givenNameFirst = "\(metadata.givenName) \(metadata.familyName)" as NSString
            familyNameFirst = "\(metadata.familyName) \(metadata.givenName)" as NSString
            phones = contact.phones.map { Address($0.number, name: metadata.displayName) }
            allEmails = contact.emails.map { $0.address as NSString }
            sipEmails = contact.emails.compactMap {
                guard let rawLabel = $0.rawLabel,
                      (rawLabel as NSString).caseInsensitiveCompare("sip") == .orderedSame else { return nil }
                return Address($0.address, name: metadata.displayName)
            }
        }
    }
}

private func prefix(_ value: NSString, _ substring: String, insensitive: Bool) -> Bool {
    value.range(of: substring, options: insensitive ? [.anchored, .caseInsensitive] : [.anchored]).location == 0
}

private func equal(_ value: NSString, _ other: String) -> Bool {
    value.caseInsensitiveCompare(other) == .orderedSame
}

private func nameSplits(_ name: String) -> [(String, String)] {
    let components = name.components(separatedBy: " ")
    guard components.count > 1 else { return [] }
    func join(_ parts: ArraySlice<String>) -> String {
        parts.reduce("") { $0.isEmpty ? $1 : $0 + " " + $1 }
    }
    return (0..<(components.count - 1)).map {
        (join(components[...$0]), join(components[($0 + 1)...]))
    }
}
