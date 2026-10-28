import Cocoa
@preconcurrency import Contacts
@testable import UseCases
import XCTest
@testable import Telephone

// Synthetic boundaries only: no CNContactStore, Contacts prompt, system-settings
// launch, SIP account, real address book or persisted defaults are used here.
@MainActor
final class ContactsRecoveryTests: XCTestCase {
    func testUndeterminedContactsDoNotFetchOrRequestAccessDuringEnumeration() async {
        await verifyUnavailableEnumeration(.notDetermined, failure: .notDetermined)
    }

    func testDeniedContactsDoNotFetchOrRequestAccessDuringEnumeration() async {
        await verifyUnavailableEnumeration(.denied, failure: .denied)
    }

    func testRestrictedContactsDoNotFetchOrRequestAccessDuringEnumeration() async {
        await verifyUnavailableEnumeration(.restricted, failure: .restricted)
    }

    func testAuthorizedContactsPublishCompleteSyntheticSnapshot() async {
        await verifyAllowedEnumeration(.authorized)
    }

    func testUnknownAuthorizationCannotFetchOrRequestAccess() async {
        await verifyUnavailableEnumeration(CNAuthorizationStatus(rawValue: 4)!, failure: .restricted)
    }

    func testSystemAuthorizationDeniedErrorDiscardsSnapshotEvenIfStatusStillAuthorized() async {
        await verifyFetchAuthorizationDenied()
    }

    func testFetchErrorDiscardsAlreadyEnumeratedContacts() async {
        await verifyDiscardedEnumeration(revokeAccess: false, failure: .transient)
    }

    func testPermissionRevokedDuringFetchDiscardsSnapshotWithTypedFailure() async {
        await verifyDiscardedEnumeration(revokeAccess: true, failure: .denied)
    }

    func testExplicitAdapterRequestOnlyPromptsWhileUndetermined() async {
        await verifyExplicitRequests()
    }

    func testAdapterRequestFailureIsRecoverableWithoutFetching() async {
        await verifyRequestFailure()
    }

    func testPresentationDistinguishesEveryAccessAndLoadStateWithoutLeakingSystemErrors() {
        let (index, _) = makeIndex()
        var reloads = 0
        let controller = ContactsRecoveryController(index: index, requestAccess: { false }, center: NotificationCenter(),
                                                    openSettings: {}, reloadHistory: { reloads += 1 })
        let presentations: [(ContactsLoadState, String, String, Bool)] = [
            (.notLoaded, "Contacts: Not checked", "Check Contacts", true),
            (.loading, "Contacts: Checking…", "Retry", false),
            (.ready, "Contacts: Available", "Refresh", true),
            (.unavailable(.notDetermined), "Contacts: Access not requested. Allow access to show names.", "Allow Contacts", true),
            (.unavailable(.denied), "Contacts: Access denied. Enable it in System Settings.", "Open Settings…", true),
            (.unavailable(.restricted), "Contacts: Access restricted by system policy.", "Restricted", false),
            (.unavailable(.transient), "Contacts: Could not refresh. Previous matches kept; retry.", "Retry", true),
            (.unavailable(.transientWithoutCache), "Contacts: Could not refresh. Retry to load permitted names.", "Retry", true)
        ]
        for (state, text, action, enabled) in presentations {
            controller.receive(state)
            XCTAssertEqual(controller.statusText, text)
            XCTAssertEqual(controller.actionTitle, action)
            XCTAssertEqual(controller.actionEnabled, enabled)
        }
        XCTAssertEqual(reloads, 6, "Completed states should reload history names; loading/notLoaded should not")
        XCTAssertFalse(controller.statusText.contains("Previous matches kept"), "Narrowed access must not imply cached names remain available")
    }

    func testRefreshAndAppActivationRecheckWithoutRequestingPermission() async {
        let relay = ContactsStatusRelay()
        let (index, factory) = makeIndex(relay: relay)
        let requests = RecoveryRequestGate()
        let center = NotificationCenter()
        let controller = ContactsRecoveryController(index: index, requestAccess: { await requests.request() }, center: center, openSettings: {})
        relay.controller = controller
        controller.refresh()
        await waitUntil { controller.actionEnabled && controller.actionTitle == "Allow Contacts" }
        let firstCount = await factory.makeCount
        XCTAssertEqual(firstCount, 1)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await waitUntil { await factory.makeCount == 2 && controller.actionEnabled }
        let requestCount = await requests.requestCount
        XCTAssertEqual(requestCount, 0, "Neither passive recheck is an explicit permission action")
        let finalCount = await factory.makeCount
        XCTAssertEqual(finalCount, 2, "A completed unavailable state must not retry itself indefinitely")
    }

    func testExplicitAllowHasOnePermissionRequestInFlightAndDoesNotLoopAfterFailure() async {
        let relay = ContactsStatusRelay()
        let (index, factory) = makeIndex(relay: relay)
        let requests = RecoveryRequestGate()
        let controller = ContactsRecoveryController(index: index, requestAccess: { await requests.request() }, center: NotificationCenter(), openSettings: {})
        relay.controller = controller
        controller.receive(.unavailable(.notDetermined))
        controller.performAction()
        controller.performAction()
        await waitUntil { await requests.requestCount == 1 }
        XCTAssertFalse(controller.actionEnabled)
        await requests.finish(false)
        await waitUntil { controller.actionEnabled && controller.statusText == "Contacts: Access request failed. Try Allow Contacts again." }
        let requestCount = await requests.requestCount
        let refreshCount = await factory.makeCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(refreshCount, 1)
        controller.refresh()
        await waitUntil { controller.actionEnabled && controller.actionTitle == "Allow Contacts" }
        let retriedRequests = await requests.requestCount
        let retriedRefreshes = await factory.makeCount
        XCTAssertEqual(retriedRequests, 1, "Retrying the index must not implicitly repeat a permission request")
        XCTAssertEqual(retriedRefreshes, 2)
    }

    func testSuccessfulExplicitAllowRefreshesIndexWithoutAnotherPrompt() async {
        let relay = ContactsStatusRelay()
        let (index, factory) = makeIndex(result: .success(RecoveryEmptyIndex()), relay: relay)
        let requests = RecoveryRequestGate()
        let controller = ContactsRecoveryController(index: index, requestAccess: { await requests.request() }, center: NotificationCenter(), openSettings: {})
        relay.controller = controller
        controller.receive(.unavailable(.notDetermined))
        controller.performAction()
        await waitUntil { await requests.requestCount == 1 }
        await requests.finish(true)
        await waitUntil { controller.actionEnabled && controller.statusText == "Contacts: Available" }
        let requestCount = await requests.requestCount
        let refreshCount = await factory.makeCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(controller.actionTitle, "Refresh")
    }

    func testDeniedOpensInjectedSettingsAndRestrictedDoesNotPromptOrRefresh() async {
        let (index, factory) = makeIndex()
        let requests = RecoveryRequestGate()
        var opens = 0
        let controller = ContactsRecoveryController(index: index, requestAccess: { await requests.request() }, center: NotificationCenter(), openSettings: { opens += 1 })
        controller.receive(.unavailable(.denied))
        controller.performAction()
        XCTAssertEqual(opens, 1)
        controller.receive(.unavailable(.restricted))
        controller.performAction()
        XCTAssertEqual(opens, 1)
        let requestCount = await requests.requestCount
        let refreshCount = await factory.makeCount
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(refreshCount, 0)
    }

    func testEveryReadySnapshotReloadsHistoryEvenIfLoadingPresentationWasCoalesced() {
        let (index, _) = makeIndex()
        var reloads = 0
        let controller = ContactsRecoveryController(index: index, requestAccess: { false }, center: NotificationCenter(),
                                                    openSettings: {}, reloadHistory: { reloads += 1 })
        controller.receive(.ready)
        controller.receive(.ready)
        XCTAssertEqual(reloads, 2, "A changed snapshot can remain ready while its loading presentation is coalesced")
    }

    func testOrderedRelayAdmitsOnlyLatestQueuedStateAfterRevocation() async {
        let (index, _) = makeIndex()
        var reloads = 0
        let controller = ContactsRecoveryController(index: index, requestAccess: { false }, center: NotificationCenter(),
                                                    openSettings: {}, reloadHistory: { reloads += 1 })
        let relay = ContactsStatusRelay()
        relay.controller = controller
        relay.enqueue(.ready)
        relay.enqueue(.unavailable(.denied))
        await waitUntil { controller.actionTitle == "Open Settings…" }
        XCTAssertEqual(controller.statusText, "Contacts: Access denied. Enable it in System Settings.")
        XCTAssertEqual(reloads, 1, "Superseded ready work must not paint or reload an older state")
    }

    func testNativeGeneralContactsRowFitsFixedSettingsWindowInLightAndDark() async throws {
        let relay = ContactsStatusRelay()
        let (index, _) = makeIndex(relay: relay)
        var settingsOpens = 0
        let controller = ContactsRecoveryController(index: index, requestAccess: { false }, center: NotificationCenter(), openSettings: { settingsOpens += 1 })
        relay.controller = controller
        let preferences = PreferencesController(windowNibName: "Preferences")
        let window = try XCTUnwrap(preferences.window)
        defer { window.orderOut(nil) }
        let general = preferences.generalPreferencesViewController
        general.contactsRecoveryController = controller
        preferences.changeView(try XCTUnwrap(preferences.generalToolbarItem))
        window.orderFront(nil)
        // General is already selected when this window opens. Its initial
        // appearance precedes injection, so explicitly settle this fixture's
        // synthetic index rather than depending on another appearance event.
        controller.refresh()
        await waitUntil { controller.actionEnabled && controller.actionTitle == "Allow Contacts" }
        let row = try XCTUnwrap(find("ContactsRecoveryStatus", in: general.view) as? NSStackView)
        let button = try XCTUnwrap(find("ContactsRecoveryAction", in: row) as? NSButton)
        let label = try XCTUnwrap(row.arrangedSubviews.first as? NSTextField)
        let fixedFrame = window.frame
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for failure in [ContactsLoadFailure.notDetermined, .denied, .restricted, .transient, .transientWithoutCache] {
                controller.receive(.unavailable(failure))
                window.contentView?.layoutSubtreeIfNeeded()
                XCTAssertEqual(window.frame, fixedFrame)
                XCTAssertTrue(general.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(row.frame), "Contacts row must fit the existing General pane")
                XCTAssertTrue(row.bounds.insetBy(dx: -0.5, dy: -0.5).contains(button.frame))
                XCTAssertEqual(label.stringValue, controller.statusText)
                XCTAssertEqual(label.toolTip, controller.statusText)
                XCTAssertEqual(button.title, controller.actionTitle)
                XCTAssertEqual(button.isEnabled, controller.actionEnabled)
                XCTAssertEqual(button.accessibilityLabel(), controller.actionTitle)
                XCTAssertEqual(button.cell?.accessibilityLabel(), controller.actionTitle)
                XCTAssertEqual(label.accessibilityLabel(), "Call history contact lookup status")
                let needed = (label.stringValue as NSString).boundingRect(
                    with: NSSize(width: label.bounds.width, height: 1_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: try XCTUnwrap(label.font)]).height
                XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, needed, "Status guidance must wrap within its two visible lines")
                if failure == .denied {
                    general.view.displayIfNeeded()
                    let bitmap = try XCTUnwrap(general.view.bitmapImageRepForCachingDisplay(in: general.view.bounds))
                    general.view.cacheDisplay(in: general.view.bounds, to: bitmap)
                    let image = NSImage(size: general.view.bounds.size)
                    image.addRepresentation(bitmap)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = appearance == .aqua ? "contacts-general-denied-light" : "contacts-general-denied-dark"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        controller.receive(.unavailable(.denied))
        XCTAssertTrue(button.isEnabled, "The settled denied-state native action must be enabled")
        button.performClick(nil)
        XCTAssertEqual(settingsOpens, 1, "Native button must route to the injected recovery action")
    }

    private func makeIndex(result: ContactMatchingIndexLoadResult = .failure(.notDetermined), relay: ContactsStatusRelay? = nil) -> (LazyDiscardingContactMatchingIndex, RecoveryIndexFactory) {
        let factory = RecoveryIndexFactory(result: result)
        return (LazyDiscardingContactMatchingIndex(factory: factory, stateDidChange: { relay?.enqueue($0) }), factory)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !(await condition()) {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                XCTFail("Synthetic Contacts operation did not reach its expected state", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        return view.subviews.lazy.compactMap { self.find(identifier, in: $0) }.first
    }
}

@ContactsActor
private func verifyUnavailableEnumeration(_ status: CNAuthorizationStatus, failure: ContactsLoadFailure) {
    var fetches = 0, requests = 0
    var names: [String] = []
    let adapter = CNContactStoreToContactsAdapter(authorization: { status }, fetch: { _ in fetches += 1 }, request: { requests += 1; return true })
    let result = adapter.enumerate { names.append($0.name) }
    guard case .failure(let actual) = result else { return XCTFail("Unavailable access must return a typed failure") }
    XCTAssertEqual(actual, failure)
    XCTAssertEqual(fetches, 0)
    XCTAssertEqual(requests, 0)
    XCTAssertTrue(names.isEmpty)
}

@ContactsActor
private func verifyAllowedEnumeration(_ status: CNAuthorizationStatus) {
    var fetches = 0, requests = 0
    var names: [String] = []
    let adapter = CNContactStoreToContactsAdapter(authorization: { status }, fetch: { body in
        fetches += 1
        body(Contact(name: "Synthetic Contact", phones: [], emails: []))
    }, request: { requests += 1; return true })
    let result = adapter.enumerate { names.append($0.name) }
    guard case .success = result else { return XCTFail("Authorized access must allow enumeration") }
    XCTAssertEqual(names, ["Synthetic Contact"])
    XCTAssertEqual(fetches, 1)
    XCTAssertEqual(requests, 0)
}

@ContactsActor
private func verifyDiscardedEnumeration(revokeAccess: Bool, failure: ContactsLoadFailure) {
    let authorization = RecoveryAuthorization(.authorized)
    var names: [String] = []
    let adapter = CNContactStoreToContactsAdapter(authorization: { authorization.status }, fetch: { body in
        body(Contact(name: "Synthetic Partial Contact", phones: [], emails: []))
        if revokeAccess { authorization.status = .denied }
        else { throw RecoveryFetchError.failed }
    }, request: { XCTFail("Enumeration must not request permission"); return false })
    let result = adapter.enumerate { names.append($0.name) }
    guard case .failure(let actual) = result else { return XCTFail("Incomplete/revoked snapshot must fail") }
    XCTAssertEqual(actual, failure)
    XCTAssertTrue(names.isEmpty, "The caller must never receive any part of an unusable snapshot")
}

@ContactsActor
private func verifyFetchAuthorizationDenied() {
    var names: [String] = []
    let adapter = CNContactStoreToContactsAdapter(authorization: { .authorized }, fetch: { body in
        body(Contact(name: "Synthetic Inaccessible Contact", phones: [], emails: []))
        throw NSError(domain: CNErrorDomain, code: CNError.Code.authorizationDenied.rawValue)
    }, request: { XCTFail("A fetch error must not request permission"); return false })
    let result = adapter.enumerate { names.append($0.name) }
    guard case .failure(let failure) = result else { return XCTFail("A system access error must fail the fetch") }
    XCTAssertEqual(failure, .denied)
    XCTAssertTrue(names.isEmpty)
}

@ContactsActor
private func verifyExplicitRequests() async {
    for status in [CNAuthorizationStatus.authorized, .denied, .restricted, CNAuthorizationStatus(rawValue: 4)!, .notDetermined] {
        var requests = 0
        let adapter = CNContactStoreToContactsAdapter(authorization: { status }, fetch: { _ in XCTFail("Requesting access must not enumerate") }, request: { requests += 1; return false })
        let completed = await adapter.requestAccessIfNeeded()
        XCTAssertTrue(completed, "A completed denied grant is distinguished from a failed request")
        XCTAssertEqual(requests, status == .notDetermined ? 1 : 0)
    }
}

@ContactsActor
private func verifyRequestFailure() async {
    var requests = 0
    let adapter = CNContactStoreToContactsAdapter(authorization: { .notDetermined }, fetch: { _ in XCTFail("Request failure must not enumerate") }, request: { requests += 1; throw RecoveryFetchError.failed })
    let completed = await adapter.requestAccessIfNeeded()
    XCTAssertFalse(completed)
    XCTAssertEqual(requests, 1)
}

private enum RecoveryFetchError: Error { case failed }

// Locked synthetic authorisation permits revocation inside a fetch while the
// production adapter's @Sendable authorisation closure remains race-free.
private final class RecoveryAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CNAuthorizationStatus
    init(_ value: CNAuthorizationStatus) { self.value = value }
    var status: CNAuthorizationStatus {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@ContactsActor
private final class RecoveryIndexFactory: ContactMatchingIndexFactory {
    private let result: ContactMatchingIndexLoadResult
    private(set) var makeCount = 0
    nonisolated init(result: ContactMatchingIndexLoadResult) { self.result = result }
    func make() async -> ContactMatchingIndexLoadResult { makeCount += 1; return result }
}

@ContactsActor
private final class RecoveryEmptyIndex: ContactMatchingIndex {
    nonisolated init() {}
    func contact(forPhone phone: ExtractedPhoneNumber) async -> MatchedContact? { nil }
    func contact(forEmail email: NormalizedLowercasedString) async -> MatchedContact? { nil }
}

private actor RecoveryRequestGate {
    private(set) var requestCount = 0
    private var continuation: CheckedContinuation<Bool, Never>?
    func request() async -> Bool {
        requestCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: Bool) { continuation?.resume(returning: result); continuation = nil }
}

// Typed bridge used by the Objective-C native token-field tests. Constructing
// these values neither constructs nor reads a CNContactStore/ABAddressBook, and
// authorization is an injected Boolean rather than an OS permission operation.
@MainActor
@objc(JPSDiallerCompletionFixture)
final class DiallerCompletionFixture: NSObject {
    @objc(providerWithScenario:)
    static func provider(scenario: Int) -> JPSDiallerContacts {
        let contacts: [Contact]
        switch scenario {
        case 1:
            contacts = [
                contact("multi", given: "Mary Jane", family: "Van Dyke", phones: [("300", "home")]),
                contact("company", given: "Company Given", family: "Company Family", organisation: "First Responders",
                        isCompany: true, phones: [("400", "work")]),
                contact("person-org", given: "Person", family: "Employee", organisation: "Person Organisation",
                        phones: [("450", "work")]),
                contact("given", given: "Prince", phones: [("500", "home")]),
                contact("family", family: "Solo", phones: [("600", "mobile")]),
                contact("unicode", given: "Zoë", family: "O'Neill", phones: [("700", "home")]),
                contact("unnamed", phones: [("800", "home")]),
                contact("empty-company", given: "Ignored", family: "Name", isCompany: true, phones: [("850", "work")]),
                contact("empty", given: "No destinations")
            ]
        case 2:
            contacts = [
                contact("first", given: "Ada", family: "Lovelace", phones: [("100", "home"), ("100", "mobile"), ("200", "work")]),
                contact("second", given: "Ada", family: "Lovelace", phones: [("100", "home"), ("900", "work")])
            ]
        case 4:
            contacts = [contact("formatted", given: "Ada", family: "Lovelace",
                                phones: [("123 456 7890", "home"), ("123-456-7890", "mobile")])]
        case 5:
            contacts = [contact("family-order", given: "Ada", family: "Lovelace", displayName: "Lovelace Ada",
                                phones: [("100", "home"), ("200", "mobile")])]
        case 6:
            contacts = [contact("sip-duplicates", given: "Ada", family: "Lovelace", phones: [("100", "home")],
                                emails: [("Ada@pbx.invalid", "sip"), ("ADA@PBX.INVALID", "SIP")])]
        default:
            contacts = [contact("ada", given: "Ada", family: "Lovelace", phones: [("100", "home"), ("200", "mobile")],
                                emails: [("private@pbx.invalid", "home"), ("Ada@pbx.invalid", "sip"),
                                         ("team@pbx.invalid", "SIP"), ("near@pbx.invalid", " sip ")])]
        }
        return JPSDiallerContacts(snapshot: ContactCompletionSnapshot(contacts: contacts), authorization: { scenario != 3 })
    }

    private static func contact(_ identifier: String, given: String = "", family: String = "", organisation: String = "",
                                isCompany: Bool = false, displayName: String? = nil,
                                phones: [(String, String)] = [], emails: [(String, String)] = []) -> Contact {
        let fullName = displayName ?? (isCompany ? organisation : [given, family].filter { !$0.isEmpty }.joined(separator: " "))
        return Contact(name: fullName,
                       phones: phones.map { number, label in
                           let rawLabel: String
                           switch label {
                           case "home": rawLabel = CNLabelHome
                           case "mobile": rawLabel = CNLabelPhoneNumberMobile
                           case "work": rawLabel = CNLabelWork
                           default: rawLabel = label
                           }
                           // Use the existing English label table for built-ins;
                           // genuine custom labels retain their adapter value.
                           return .init(number: number, label: "synthetic adapter \(label)", rawLabel: rawLabel)
                       },
                       emails: emails.map { .init(address: $0.0, label: "synthetic adapter \($0.1)", rawLabel: $0.1) },
                       completionMetadata: .init(identifier: identifier, givenName: given, familyName: family,
                                                 organisation: organisation, isCompany: isCompany, displayName: fullName))
    }
}

// These are detached values only. No CNContactStore or AddressBook object is
// constructed, and every adapter operation below is supplied by a test closure.
@MainActor
final class CNContactCompletionMappingTests: XCTestCase {
    func testPersonCompletionMetadataKeepsOnlyGivenAndFamilyNamesWhileHistoryRetainsItsFormatter() throws {
        let source = CNMutableContact()
        source.contactType = .person
        source.namePrefix = "Dr"
        source.givenName = "Ada"
        source.middleName = "Augusta"
        source.familyName = "Lovelace"
        source.nameSuffix = "Jr"
        source.organizationName = "Synthetic Employer"

        let mapped = Contact(source)
        let metadata = try XCTUnwrap(mapped.completionMetadata)
        XCTAssertEqual(mapped.name, CNContactFormatter.string(from: source, style: .fullName) ?? "")
        XCTAssertEqual(metadata.identifier, source.identifier)
        XCTAssertEqual(metadata.givenName, "Ada")
        XCTAssertEqual(metadata.familyName, "Lovelace")
        XCTAssertEqual(metadata.organisation, "Synthetic Employer")
        XCTAssertFalse(metadata.isCompany)
        let expected = CNContactFormatter.nameOrder(for: source) == .familyNameFirst
            ? "Lovelace Ada" : "Ada Lovelace"
        XCTAssertEqual(metadata.displayName, expected)
        XCTAssertFalse(metadata.displayName.contains("Augusta"))
        XCTAssertFalse(metadata.displayName.contains("Dr"))
        XCTAssertFalse(metadata.displayName.contains("Jr"))
    }

    func testRawLabelsAndOrderedRepeatedSIPLabelsSurviveMappingWithoutPromotingOrdinaryEmail() throws {
        let source = CNMutableContact()
        source.givenName = "Synthetic"
        source.familyName = "Labels"
        source.phoneNumbers = [
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "100")),
            CNLabeledValue(label: "Custom desk", value: CNPhoneNumber(stringValue: "200"))
        ]
        source.emailAddresses = [
            CNLabeledValue(label: "sip", value: "first@pbx.invalid" as NSString),
            CNLabeledValue(label: "SIP", value: "second@pbx.invalid" as NSString),
            CNLabeledValue(label: CNLabelWork, value: "ordinary@example.invalid" as NSString),
            CNLabeledValue(label: nil, value: "unlabelled@example.invalid" as NSString)
        ]

        let mapped = Contact(source)
        XCTAssertEqual(mapped.phones.map(\.number), ["100", "200"])
        XCTAssertEqual(mapped.phones.map(\.rawLabel), [CNLabelHome, "Custom desk"])
        XCTAssertEqual(mapped.phones[0].label, CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelHome))
        XCTAssertEqual(mapped.phones[1].label, "Custom desk")
        XCTAssertEqual(mapped.emails.map(\.rawLabel), ["sip", "SIP", CNLabelWork, nil])
        XCTAssertEqual(mapped.emails.map(\.address), ["first@pbx.invalid", "second@pbx.invalid", "ordinary@example.invalid", "unlabelled@example.invalid"])
        let snapshot = ContactCompletionSnapshot(contacts: [mapped])
        XCTAssertEqual(snapshot.completionStrings(for: "Synthetic"), [
            "Synthetic Labels <100>", "Synthetic Labels <200>",
            "Synthetic Labels <first@pbx.invalid>", "Synthetic Labels <second@pbx.invalid>"
        ])
        XCTAssertTrue(snapshot.completionStrings(for: "ordinary").isEmpty)
        XCTAssertTrue(snapshot.completionStrings(for: "unlabelled").isEmpty)
    }

    func testCompanyCompletionUsesOrganisationAndIgnoresPersonFields() throws {
        let source = CNMutableContact()
        source.contactType = .organization
        source.givenName = "Ignored Given"
        source.familyName = "Ignored Family"
        source.organizationName = "Synthetic Organisation"
        source.phoneNumbers = [CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "300"))]

        let mapped = Contact(source)
        let metadata = try XCTUnwrap(mapped.completionMetadata)
        XCTAssertTrue(metadata.isCompany)
        XCTAssertEqual(metadata.displayName, "Synthetic Organisation")
        XCTAssertEqual(mapped.name, CNContactFormatter.string(from: source, style: .fullName) ?? "")
        let snapshot = ContactCompletionSnapshot(contacts: [mapped])
        XCTAssertEqual(snapshot.completionStrings(for: "Synthetic"), ["Synthetic Organisation <300>"])
        XCTAssertTrue(snapshot.completionStrings(for: "Ignored").isEmpty)
    }

    func testSparsePersonNamesDoNotInventOrganisationOrExtraWhitespace() throws {
        for (given, family, expected) in [("Onlygiven", "", "Onlygiven"), ("", "Onlyfamily", "Onlyfamily"), ("", "", "")] {
            let source = CNMutableContact()
            source.contactType = .person
            source.givenName = given
            source.familyName = family
            source.organizationName = "Not a Company Record"
            let metadata = try XCTUnwrap(Contact(source).completionMetadata)
            XCTAssertEqual(metadata.displayName, expected)
            XCTAssertFalse(metadata.isCompany)
        }
    }

    func testOneInjectedEnumerationPublishesMappedHistoryAndCompletionWithoutRequestingAccess() async {
        await verifyMappedSingleEnumeration()
    }
}

@ContactsActor
private func verifyMappedSingleEnumeration() {
    let source = CNMutableContact()
    source.givenName = "Synthetic"
    source.middleName = "History Middle"
    source.familyName = "Person"
    source.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "1234"))]
    var fetches = 0
    var requests = 0
    let adapter = CNContactStoreToContactsAdapter(authorization: { .authorized }, fetch: { body in
        fetches += 1
        body(Contact(source))
    }, request: { requests += 1; return false })

    let index = SimpleContactMatchingIndex(contacts: adapter, maxPhoneNumberLength: 4)
    XCTAssertEqual(fetches, 1)
    XCTAssertEqual(requests, 0)
    XCTAssertEqual(index.contact(forPhone: ExtractedPhoneNumber("1234", maxLength: 4))?.name,
                   CNContactFormatter.string(from: source, style: .fullName) ?? "")
    XCTAssertEqual(index.completionSnapshot?.completionStrings(for: "Synthetic"), ["Synthetic Person <1234>"])
    XCTAssertEqual(fetches, 1, "Synchronous snapshot queries must not enumerate again")
    XCTAssertEqual(requests, 0)
}
