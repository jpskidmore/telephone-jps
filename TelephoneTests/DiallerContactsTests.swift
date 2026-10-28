import Cocoa
import Foundation
@preconcurrency import Contacts
import UseCases
import XCTest
@testable import Telephone

@MainActor
final class DiallerContactsTests: XCTestCase {
    private func snapshot(_ name: String = "Ada") -> ContactCompletionSnapshot {
        ContactCompletionSnapshot(contacts: [Contact(
            name: "History name with extra components", phones: [.init(number: "100", label: "home", rawLabel: CNLabelHome)],
            emails: [], completionMetadata: .init(identifier: name, givenName: name, familyName: "Lovelace",
                organisation: "", isCompany: false, displayName: "\(name) Lovelace"))])
    }

    func testEmptyProviderDoesNotCheckAuthorizationOrConstructDirectory() {
        var checks = 0
        let sut = JPSDiallerContacts(authorization: { checks += 1; return true })
        XCTAssertEqual(sut.completions(for: "Ada"), [])
        XCTAssertNil(sut.firstContact(matchingUser: "100", sipAddress: "100", displayName: ""))
        XCTAssertEqual(checks, 0)
    }

    func testLocalizedLabelCannotInventAnUnknownRawSIPDestination() throws {
        let contact = Contact(name: "Ada", phones: [.init(number: "100", label: "home")],
            emails: [.init(address: "ordinary@example.invalid", label: "sip")],
            completionMetadata: .init(identifier: "1", givenName: "Ada", familyName: "Lovelace",
                organisation: "", isCompany: false, displayName: "Ada Lovelace"))
        let sut = JPSDiallerContacts(snapshot: .init(contacts: [contact]), authorization: { true })
        let match = try XCTUnwrap(sut.firstContact(matchingUser: "100", sipAddress: "100", displayName: ""))
        XCTAssertEqual(match.destinations.map(\.address), ["100"])
        XCTAssertEqual(sut.completions(for: "Ada"), ["Ada Lovelace <100>"])
    }

    func testInvalidationFencesQueuedPublicationBeforeMainHop() async {
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { true })
        let old = sut.currentTicket()
        let pending = sut.enqueue(old, snapshot: snapshot("Old"))
        sut.invalidate()
        await pending.value
        XCTAssertEqual(sut.completions(for: "Old"), [])
        XCTAssertEqual(sut.completions(for: "Ada"), [])
    }

    func testNewScopeSurvivesLateOldSuccessAndFailurePublication() async {
        let sut = JPSDiallerContacts(authorization: { true })
        let old = sut.currentTicket()
        sut.invalidate()
        let new = sut.currentTicket()
        await sut.enqueue(new, snapshot: snapshot("New")).value
        await sut.enqueue(old, snapshot: snapshot("Old")).value
        await sut.enqueue(old, snapshot: nil).value
        XCTAssertEqual(sut.completions(for: "New"), ["New Lovelace <100>"])
        XCTAssertEqual(sut.completions(for: "Old"), [])
    }

    func testDeniedReadClearsSnapshotAndCannotReturnAfterStatusReallowsWithoutReload() {
        var authorized = true
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { authorized })
        XCTAssertFalse(sut.completions(for: "Ada").isEmpty)
        authorized = false
        XCTAssertEqual(sut.completions(for: "Ada"), [])
        authorized = true
        XCTAssertEqual(sut.completions(for: "Ada"), [])
    }

    func testAuthorizationChangeDuringCompletionCannotReturnComputedResults() {
        var checks = 0
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { checks += 1; return checks == 1 })
        XCTAssertEqual(sut.completions(for: "Ada"), [])
        XCTAssertNil(sut.firstContact(matchingUser: "100", sipAddress: "100", displayName: ""))
    }

    func testAuthorizationChangeDuringMatchConstructionCannotReturnEnrichment() {
        var checks = 0
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { checks += 1; return checks == 1 })
        XCTAssertNil(sut.firstContact(matchingUser: "100", sipAddress: "100", displayName: ""))
        XCTAssertEqual(sut.completions(for: "Ada"), [])
    }

    func testOldMatchValidationCannotEraseNewSnapshot() async throws {
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { true })
        let old = try XCTUnwrap(sut.firstContact(matchingUser: "100", sipAddress: "100", displayName: ""))
        sut.invalidate()
        await sut.enqueue(sut.currentTicket(), snapshot: snapshot("New")).value
        XCTAssertFalse(sut.isCurrent(old))
        XCTAssertEqual(sut.completions(for: "New"), ["New Lovelace <100>"])
    }

    func testSuspensionRejectsEvenCurrentTicketUntilResumeAndFreshLoad() async {
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { true })
        sut.setSuspended(true)
        let suspended = sut.currentTicket()
        await sut.enqueue(suspended, snapshot: snapshot("Stale")).value
        XCTAssertEqual(sut.completions(for: "Stale"), [])
        sut.setSuspended(false)
        await sut.enqueue(suspended, snapshot: snapshot("Stale")).value
        XCTAssertEqual(sut.completions(for: "Stale"), [])
        await sut.enqueue(sut.currentTicket(), snapshot: snapshot("Fresh")).value
        XCTAssertEqual(sut.completions(for: "Fresh"), ["Fresh Lovelace <100>"])
    }

    func testStoreChangeInvalidatesBeforeBusyContactsActorCanProcessNotification() async {
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { true })
        let center = NotificationCenter()
        let target = DiallerContactsChangeProbe()
        let source = CNContactStoreContactsChangeEventSource(center: center, target: target,
            willChange: { sut.invalidate() })
        let gate = DiallerContactsBlockingGate()
        let blocker = Task { @ContactsActor in gate.block() }
        await until { gate.entered }
        center.post(name: .CNContactStoreDidChange, object: nil)
        XCTAssertEqual(sut.completions(for: "Ada"), [], "Producer admission must not wait for the actor")
        gate.release()
        await blocker.value
        await until { await target.changes == 1 }
        withExtendedLifetime(source) {}
    }

    func testExplicitRefreshInvalidatesBeforeAsyncLoadWithoutPermissionRequest() async {
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { true })
        let factory = DiallerContactsEmptyFactory()
        let index = LazyDiscardingContactMatchingIndex(factory: factory)
        let prompts = DiallerContactsRequestProbe()
        let controller = ContactsRecoveryController(index: index, requestAccess: { await prompts.request() },
            center: NotificationCenter(), openSettings: {}, completionInvalidated: { sut.invalidate() })
        controller.refresh()
        XCTAssertEqual(sut.completions(for: "Ada"), [])
        await until { controller.actionEnabled }
        let requests = await prompts.count
        XCTAssertEqual(requests, 0)
    }

    func testBackgroundActivationInvalidatesBeforeMainActorRecheck() async {
        let sut = JPSDiallerContacts(snapshot: snapshot(), authorization: { true })
        let center = NotificationCenter()
        let index = LazyDiscardingContactMatchingIndex(factory: DiallerContactsEmptyFactory())
        let controller = ContactsRecoveryController(index: index, requestAccess: { false }, center: center,
            openSettings: {}, completionInvalidated: { sut.invalidate() })
        await Task.detached { center.post(name: NSApplication.didBecomeActiveNotification, object: nil) }.value
        XCTAssertEqual(sut.completions(for: "Ada"), [])
        withExtendedLifetime(controller) {}
    }

    private func until(_ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for isolated Contacts boundary")
    }
}

private final class DiallerContactsBlockingGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var started = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func block() { lock.lock(); started = true; lock.unlock(); _ = semaphore.wait(timeout: .now() + 5) }
    func release() { semaphore.signal() }
}

@ContactsActor
private final class DiallerContactsChangeProbe: ContactsChangeEventTarget {
    private(set) var changes = 0
    nonisolated init() {}
    func contactsDidChange() { changes += 1 }
}

@ContactsActor
private final class DiallerContactsEmptyFactory: ContactMatchingIndexFactory {
    nonisolated init() {}
    func make() async -> ContactMatchingIndexLoadResult { .success(DiallerContactsEmptyIndex()) }
}

@ContactsActor
private final class DiallerContactsEmptyIndex: ContactMatchingIndex {
    func contact(forPhone phone: ExtractedPhoneNumber) async -> MatchedContact? { nil }
    func contact(forEmail email: NormalizedLowercasedString) async -> MatchedContact? { nil }
}

private actor DiallerContactsRequestProbe {
    private(set) var count = 0
    func request() -> Bool { count += 1; return true }
}
