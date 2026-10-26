//
//  LazyDiscardingContactMatchingIndexTests.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Foundation
import Testing
@testable import UseCases
import UseCasesTestDoubles

@ContactsActor
struct LazyDiscardingContactMatchingIndexTests {
    @Test func doesNotCreateOriginOnCreation() {
        let factory = ContactMatchingIndexFactorySpy()

        _ = LazyDiscardingContactMatchingIndex(factory: factory)

        #expect(!factory.didCallMake)
    }

    @Test func createsOriginOnFirstSearchByPhone() async {
        let factory = ContactMatchingIndexFactorySpy()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)

        _ = await sut.contact(forPhone: ExtractedPhoneNumber("any", maxLength: 0))

        #expect(factory.didCallMake)
    }

    @Test func createsOriginOnFirsthSearchByEmail() async {
        let factory = ContactMatchingIndexFactorySpy()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)

        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        #expect(factory.didCallMake)
    }

    @Test func createsOriginOnce() async {
        let factory = ContactMatchingIndexFactorySpy()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)

        _ = await sut.contact(forPhone: ExtractedPhoneNumber("any", maxLength: 10))
        _ = await sut.contact(forPhone: ExtractedPhoneNumber("any", maxLength: 10))
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        #expect(factory.makeCallCount == 1)
    }

    @Test func returnsMatchFromOriginOnSearchByPhone() async {
        let contact = MatchedContact(name: "any-name", address: .phone(number: "any-number", label: "any-label"))
        let sut = LazyDiscardingContactMatchingIndex(
            factory: ContactMatchingIndexFactoryStub(indexes: [ContactMatchingIndexStub(contact: contact)])
        )

        let result = await sut.contact(forPhone: ExtractedPhoneNumber("any", maxLength: 0))

        #expect(result == contact)
    }

    @Test func returnsMatchFromOriginOnSearchByEmail() async {
        let contact = MatchedContact(name: "any-name", address: .email(address: "any-address", label: "any-label"))
        let sut = LazyDiscardingContactMatchingIndex(
            factory: ContactMatchingIndexFactoryStub(indexes: [ContactMatchingIndexStub(contact: contact)])
        )

        let result = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        #expect(result == contact)
    }

    @Test func doesNotCreateOriginOnContactsDidChange() {
        let factory = ContactMatchingIndexFactorySpy()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)

        sut.contactsDidChange()

        #expect(!factory.didCallMake)
    }

    @Test func returnsMatchFromRecreatedOriginAfterContactsChangeEventOnSearchByPhone() async {
        let contact = MatchedContact(name: "any-name-2", address: .phone(number: "any-number-2", label: "any-label-2"))
        let sut = LazyDiscardingContactMatchingIndex(
            factory: ContactMatchingIndexFactoryStub(
                indexes: [
                    ContactMatchingIndexStub(
                        contact: MatchedContact(
                            name: "any-name-1", address: .phone(number: "any-number-1", label: "any-label-1")
                        )
                    ),
                    ContactMatchingIndexStub(contact: contact)
                ]
            )
        )

        _ = await sut.contact(forPhone: ExtractedPhoneNumber("any", maxLength: 0))
        sut.contactsDidChange()
        let result = await sut.contact(forPhone: ExtractedPhoneNumber("any", maxLength: 0))

        #expect(result == contact)
    }

    @Test func returnsMatchFromRecreatedOriginAfterContactsChangeEventOnSearchByEmail() async {
        let contact = MatchedContact(name: "any-name-2", address: .email(address: "any-address-2", label: "any-label-2"))
        let sut = LazyDiscardingContactMatchingIndex(
            factory: ContactMatchingIndexFactoryStub(
                indexes: [
                    ContactMatchingIndexStub(
                        contact: MatchedContact(
                            name: "any-name-1", address: .email(address: "any-address-1", label: "any-label-1")
                        )
                    ),
                    ContactMatchingIndexStub(contact: contact)
                ]
            )
        )

        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))
        sut.contactsDidChange()
        let result = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        #expect(result == contact)
    }

    @Test func reportsSuccessfulNoMatchSeparatelyFromUnavailableContacts() async {
        let sut = LazyDiscardingContactMatchingIndex(factory: ContactMatchingIndexFactorySpy())
        #expect(sut.loadState == .notLoaded)

        let result = await sut.contact(forEmail: NormalizedLowercasedString("unknown@example.invalid"))

        #expect(result == nil)
        #expect(sut.loadState == .ready)
    }

    @Test func retainsLastCompleteSnapshotAfterTransientFailure() async {
        let contact = syntheticMatchedContact()
        let factory = ContactMatchingIndexFactoryStub(results: [
            .success(ContactMatchingIndexStub(contact: contact)), .failure(.transient)
        ])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        await sut.refresh()
        let result = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        #expect(result == contact)
        #expect(sut.loadState == .unavailable(.transient))
        #expect(factory.makeCallCount == 2)
    }

    @Test func successfulEmptyRefreshRemovesNamesFromPreviousSnapshot() async {
        let factory = ContactMatchingIndexFactoryStub(results: [
            .success(ContactMatchingIndexStub(contact: syntheticMatchedContact())),
            .success(ContactMatchingIndexDummy())
        ])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        await sut.refresh()

        #expect(await sut.contact(forEmail: NormalizedLowercasedString("any")) == nil)
        #expect(sut.loadState == .ready)
    }

    @Test func publishesLoadingAndOutcomeForInitialLoadAndExplicitRecovery() async {
        let recorder = ContactsLoadStateRecorder()
        let factory = ContactMatchingIndexFactoryStub(results: [
            .failure(.notDetermined), .success(ContactMatchingIndexDummy())
        ])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory) { recorder.append($0) }

        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))
        await sut.refresh()

        #expect(recorder.states == [.loading, .unavailable(.notDetermined), .loading, .ready])
    }

    @Test(arguments: [ContactsLoadFailure.notDetermined, .denied, .restricted, .transientWithoutCache])
    func clearsCachedContactInformationWhenAccessIsUnavailable(_ failure: ContactsLoadFailure) async {
        let factory = ContactMatchingIndexFactoryStub(results: [
            .success(ContactMatchingIndexStub(contact: syntheticMatchedContact())), .failure(failure)
        ])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        sut.contactsDidChange()
        let emailResult = await sut.contact(forEmail: NormalizedLowercasedString("any"))
        let phoneResult = await sut.contact(forPhone: ExtractedPhoneNumber("123", maxLength: 3))

        #expect(emailResult == nil)
        #expect(phoneResult == nil)
        #expect(sut.loadState == .unavailable(failure))
    }

    @Test func doesNotRetryFailedLoadOnEveryLookup() async {
        let factory = ContactMatchingIndexFactoryStub(results: [.failure(.notDetermined)])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)

        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))
        _ = await sut.contact(forPhone: ExtractedPhoneNumber("123", maxLength: 3))

        #expect(factory.makeCallCount == 1)
        #expect(sut.loadState == .unavailable(.notDetermined))
    }

    @Test func explicitRetryCanRecoverWithoutRecreatingIndexOwner() async {
        let contact = syntheticMatchedContact()
        let factory = ContactMatchingIndexFactoryStub(results: [
            .failure(.denied), .success(ContactMatchingIndexStub(contact: contact))
        ])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        _ = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        await sut.refresh()
        let result = await sut.contact(forEmail: NormalizedLowercasedString("any"))

        #expect(result == contact)
        #expect(sut.loadState == .ready)
        #expect(factory.makeCallCount == 2)
    }

    @Test func clearsFullAccessSnapshotAfterFailedNarrowedFetchAndRecoversOnExplicitRetry() async {
        let retainedContact = Contact(
            name: "Selected Synthetic Contact", phones: [Contact.Phone(number: "0000", label: "Test")], emails: []
        )
        let removedContact = Contact(
            name: "Removed Synthetic Contact", phones: [Contact.Phone(number: "1111", label: "Test")],
            emails: [Contact.Email(address: "removed@example.invalid", label: "Test")]
        )
        let factory = ContactMatchingIndexFactoryStub(results: [
            .success(SimpleContactMatchingIndex(
                contacts: SimpleContacts([retainedContact, removedContact]), maxPhoneNumberLength: 4
            )),
            .failure(.transientWithoutCache),
            .success(SimpleContactMatchingIndex(contacts: SimpleContacts([retainedContact]), maxPhoneNumberLength: 4))
        ])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        let removedEmail = NormalizedLowercasedString("removed@example.invalid")
        #expect(await sut.contact(forEmail: removedEmail) == MatchedContact(contact: removedContact, emailIndex: 0))

        await sut.refresh()

        #expect(await sut.contact(forEmail: removedEmail) == nil)
        #expect(await sut.contact(forPhone: ExtractedPhoneNumber("0000", maxLength: 4)) == nil)
        #expect(sut.loadState == .unavailable(.transientWithoutCache))
        #expect(factory.makeCallCount == 2)

        await sut.refresh()

        #expect(await sut.contact(forPhone: ExtractedPhoneNumber("0000", maxLength: 4)) == MatchedContact(contact: retainedContact, phoneIndex: 0))
        #expect(await sut.contact(forEmail: removedEmail) == nil)
        #expect(await sut.contact(forPhone: ExtractedPhoneNumber("1111", maxLength: 4)) == nil)
        #expect(sut.loadState == .ready)
        #expect(factory.makeCallCount == 3)
    }

    @Test func coalescesConcurrentLookupsIntoOneLoad() async {
        let factory = SuspendedContactsIndexFactory()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        let contact = syntheticMatchedContact()

        async let email = sut.contact(forEmail: NormalizedLowercasedString("any"))
        async let phone = sut.contact(forPhone: ExtractedPhoneNumber("123", maxLength: 3))
        await factory.waitForCall(1)
        factory.complete(1, with: .success(ContactMatchingIndexStub(contact: contact)))

        #expect(await email == contact)
        #expect(await phone == contact)
        #expect(factory.makeCallCount == 1)
    }

    @Test func ignoresSupersededSuccessfulLoadAfterAccessWasRevoked() async {
        let factory = SuspendedContactsIndexFactory()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        let oldLookup = Task { await sut.contact(forEmail: NormalizedLowercasedString("any")) }
        await factory.waitForCall(1)

        let recheck = Task { await sut.refresh() }
        await factory.waitForCall(2)
        factory.complete(2, with: .failure(.denied))
        await recheck.value
        factory.complete(1, with: .success(ContactMatchingIndexStub(contact: syntheticMatchedContact())))

        #expect(await oldLookup.value == nil)
        #expect(sut.loadState == .unavailable(.denied))
        #expect(factory.makeCallCount == 2)
    }

    @Test func ignoresSupersededFailureAfterNewLoadSucceeded() async {
        let factory = SuspendedContactsIndexFactory()
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        let oldLookup = Task { await sut.contact(forEmail: NormalizedLowercasedString("any")) }
        await factory.waitForCall(1)

        let recheck = Task { await sut.refresh() }
        await factory.waitForCall(2)
        let contact = syntheticMatchedContact()
        factory.complete(2, with: .success(ContactMatchingIndexStub(contact: contact)))
        await recheck.value
        factory.complete(1, with: .failure(.restricted))

        #expect(await oldLookup.value == contact)
        #expect(sut.loadState == .ready)
    }

    @Test func rejectsInFlightMatchAfterPermissionRevocation() async {
        let origin = SuspendedContactMatchingIndex()
        let factory = ContactMatchingIndexFactoryStub(results: [.success(origin), .failure(.denied)])
        let sut = LazyDiscardingContactMatchingIndex(factory: factory)
        let lookup = Task { await sut.contact(forEmail: NormalizedLowercasedString("any")) }
        await origin.waitForLookup()

        await sut.refresh()
        origin.complete(with: syntheticMatchedContact())

        #expect(await lookup.value == nil)
        #expect(sut.loadState == .unavailable(.denied))
    }
}

@ContactsActor
private final class SuspendedContactsIndexFactory: ContactMatchingIndexFactory {
    private var pending: [Int: CheckedContinuation<ContactMatchingIndexLoadResult, Never>] = [:]
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var makeCallCount = 0

    func make() async -> ContactMatchingIndexLoadResult {
        makeCallCount += 1
        let call = makeCallCount
        return await withCheckedContinuation { continuation in
            pending[call] = continuation
            waiting.removeValue(forKey: call)?.resume()
        }
    }

    func waitForCall(_ call: Int) async {
        guard pending[call] == nil else { return }
        await withCheckedContinuation { waiting[call] = $0 }
    }

    func complete(_ call: Int, with result: ContactMatchingIndexLoadResult) {
        pending.removeValue(forKey: call)!.resume(returning: result)
    }
}

@ContactsActor
private final class SuspendedContactMatchingIndex: ContactMatchingIndex {
    private var pending: CheckedContinuation<MatchedContact?, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    func contact(forPhone phone: ExtractedPhoneNumber) async -> MatchedContact? {
        await suspendLookup()
    }

    func contact(forEmail email: NormalizedLowercasedString) async -> MatchedContact? {
        await suspendLookup()
    }

    private func suspendLookup() async -> MatchedContact? {
        await withCheckedContinuation {
            pending = $0
            waiting?.resume()
            waiting = nil
        }
    }

    func waitForLookup() async {
        guard pending == nil else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func complete(with contact: MatchedContact?) {
        pending!.resume(returning: contact)
        pending = nil
    }
}

private func syntheticMatchedContact() -> MatchedContact {
    MatchedContact(name: "Synthetic Contact", address: .email(address: "synthetic@example.invalid", label: "Test"))
}

private final class ContactsLoadStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStates: [ContactsLoadState] = []

    var states: [ContactsLoadState] {
        lock.withLock { recordedStates }
    }

    func append(_ state: ContactsLoadState) {
        lock.withLock { recordedStates.append(state) }
    }
}
