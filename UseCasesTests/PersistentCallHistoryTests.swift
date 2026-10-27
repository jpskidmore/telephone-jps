//
//  PersistentCallHistoryTests.swift
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
import UseCases
import UseCasesTestDoubles

@CallHistoryActor
struct PersistentCallHistoryTests {
    @Test func linkedRecordCanBeRemovedAfterRestartAndGlobalQualification() {
        let storage = MemoryPropertyListStorage()
        let linked = CallHistoryRecord(uri: URI(user: "desk", host: "example.invalid", displayName: ""),
                                       date: Date(timeIntervalSinceReferenceDate: 12), duration: 3,
                                       isIncoming: false, isMissed: false, recordingCallIdentifier: "call-key")
        let first = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        first.add(linked)
        let reopened = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        let qualified = reopened.allRecords[0].qualified(accountUUID: "account-a", accountName: "Provider")
        #expect(qualified.recordingCallIdentifier == "call-key")
        let stored = reopened.allRecords.first { $0.accountRecordIdentifier == qualified.accountRecordIdentifier }
        #expect(stored != nil)
        if let stored { reopened.remove(stored) }
        #expect(PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage).allRecords.isEmpty)
    }

    @Test func recordingCallKeySurvivesRestartAndUnlinkedLegacyRowsStayUnlinked() {
        let storage = MemoryPropertyListStorage()
        let base = makeRecord1()
        let linked = CallHistoryRecord(uri: base.uri, date: base.date, duration: base.duration,
                                       isIncoming: base.isIncoming, isMissed: base.isMissed,
                                       recordingCallIdentifier: "call-key")
        let history = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        let legacy = makeRecord2()
        history.add(linked)
        history.add(legacy)
        let reopened = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        #expect(reopened.allRecords == [linked, legacy])
        #expect(reopened.allRecords[0].recordingCallIdentifier == "call-key")
        #expect(reopened.allRecords[1].recordingCallIdentifier == nil)
    }

    @Test func malformedOrAbsentRecordingCallKeyIsNotInferredOrWrittenOnRead() {
        for value: Any in [42, ""] {
            let storage = FaultingHistoryStorage()
            storage.records = [["user": "desk", "host": "example.invalid", "recordingCallIdentifier": value]]
            let history = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
            #expect(history.allRecords[0].recordingCallIdentifier == nil)
            #expect(storage.saveCount == 0)
        }
    }

    @Test func canonicalOriginAndExplicitSIPPortTransportSurviveReload() {
        let storage = MemoryPropertyListStorage()
        let record = CallHistoryRecord(uri: URI(user: "office", address: ServiceAddress(host: "[2001:db8::1]", port: "5071"),
                                                displayName: "Office", transport: .tls),
                                       date: Date(timeIntervalSinceReferenceDate: 123), duration: 4, isIncoming: true, isMissed: false,
                                       canonicalDestination: "sip:office@[2001:db8::1]:5071;transport=tls",
                                       originAccountUUID: "stable-account", originAccountName: "First provider")
        let history = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        history.add(record)
        let reopened = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        #expect(reopened.allRecords == [record])
        #expect(reopened.allRecords[0].callbackDestination == record.canonicalDestination)
        #expect(reopened.allRecords[0].uri.port == "5071")
        #expect(reopened.allRecords[0].uri.transport == .tls)
    }

    @Test func legacyReadDoesNotInventCanonicalOrOriginMetadataOrWriteTheStore() {
        let storage = FaultingHistoryStorage()
        storage.records = [["user": "123456", "host": "", "name": "Old call", "date": Date(timeIntervalSinceReferenceDate: 10),
                            "duration": 4, "incoming": false, "missed": false]]
        let history = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        #expect(storage.saveCount == 0)
        #expect(history.allRecords[0].canonicalDestination == nil)
        #expect(history.allRecords[0].originAccountUUID == nil)
        #expect(history.allRecords[0].recordingCallIdentifier == nil)
        #expect(history.allRecords[0].callbackDestination == "123456")
        history.add(makeRecord2())
        #expect(storage.records[0]["canonicalDestination"] == nil)
        #expect(storage.records[0]["originAccountUUID"] == nil)
        #expect(storage.records[0]["recordingCallIdentifier"] == nil)
    }

    @Test func hostRemovalRetainsCallTimeCanonicalDestinationAndOriginMetadata() {
        let record = CallHistoryRecord(uri: URI(user: "123456", host: "old-provider", displayName: ""),
                                       date: Date(), duration: 4, isIncoming: false, isMissed: false,
                                       canonicalDestination: "+441442123456", originAccountUUID: "uuid", originAccountName: "First")
        let stripped = record.removingHost()
        #expect(stripped.uri.host.isEmpty)
        #expect(stripped.canonicalDestination == "+441442123456")
        #expect(stripped.originAccountUUID == "uuid" && stripped.originAccountName == "First")
    }

    @Test func persistsAfterAdding() {
        let storage = MemoryPropertyListStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()

        var sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        sut.add(record1)
        sut.add(record2)
        sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)

        #expect(sut.allRecords == [record1, record2])
    }

    @Test func persistsAfterRemovingIndividual() {
        let storage = MemoryPropertyListStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()

        var sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        sut.add(record1)
        sut.add(record2)
        sut.remove(record1)
        sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)

        #expect(sut.allRecords == [record2])
    }

    @Test func persistsAfterRemovingAll() {
        let storage = MemoryPropertyListStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()

        var sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        sut.add(record1)
        sut.add(record2)
        sut.removeAll()
        sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)

        #expect(sut.allRecords == [])
    }

    @Test func callsDeleteOnRemoveAll() {
        let storage = PropertyListStorageSpy()
        let sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)

        sut.removeAll()

        #expect(storage.didCallDelete)
    }

    @Test func doesNotCallSaveOnRemoveAll() {
        let storage = PropertyListStorageSpy()
        let sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)

        sut.removeAll()

        #expect(!storage.didCallSave)
    }
    @Test func failedInitialLoadDoesNotOverwriteExistingHistoryAndRetryMergesQueuedCall() {
        let storage = FaultingHistoryStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()
        var seed = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        seed.add(record1)
        let original = storage.records
        storage.failLoad = true
        seed = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        seed.add(record2)
        #expect(storage.records.count == original.count)
        #expect(storage.saveCount == 1)
        #expect(seed.persistenceError != nil)
        storage.failLoad = false
        #expect(seed.retryPersistence())
        #expect(seed.allRecords == [record1, record2])
        #expect(PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage).allRecords == seed.allRecords)
    }

    @Test func failedDeleteKeepsVisibleAndDurableRecordsUntilRetrySucceeds() {
        let storage = FaultingHistoryStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()
        let sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        sut.add(record1)
        storage.failDelete = true
        sut.removeAll()
        #expect(sut.allRecords == [record1])
        #expect(sut.persistenceError != nil)
        #expect(PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage).allRecords == [record1])
        storage.failDelete = false
        #expect(sut.retryPersistence())
        #expect(sut.allRecords.isEmpty)
        #expect(PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage).allRecords.isEmpty)
    }


    @Test func successfulRecoveryReloadsTheSubscribedHistoryView() {
        let storage = FaultingHistoryStorage()
        let persistent = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        let notifying = NotifyingCallHistory(origin: ReversedCallHistory(origin: persistent))
        let target = CallHistoryEventTargetSpy()
        notifying.updateTarget(target)
        storage.failSave = true
        notifying.add(makeRecord1())
        #expect(target.didUpdateCallCount == 1)
        storage.failSave = false
        #expect(persistent.retryPersistence())
        #expect(target.didUpdateCallCount == 2)
    }

    @Test func retiredHistoryCannotRecreateDeletedStorage() {
        let storage = FaultingHistoryStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()
        let sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        sut.add(record1)
        sut.removeAll()
        sut.invalidate()
        sut.add(record2)
        #expect(storage.records.isEmpty)
        #expect(sut.allRecords.isEmpty)
        #expect(storage.saveCount == 1)
    }

    @Test func removedAccountRetainsFailedDeletionUntilAppWideRetryWithoutAllowingLateWrites() {
        let storage = FaultingHistoryStorage()
        var sut: PersistentCallHistory? = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        weak var retained = sut
        sut?.add(makeRecord1())
        storage.failDelete = true
        sut?.removeAll()
        sut?.invalidate()
        sut?.add(makeRecord2())
        #expect(storage.saveCount == 1)
        sut = nil
        #expect(retained != nil)
        storage.failDelete = false
        #expect(PersistentCallHistory.retryFailedWrites())
        #expect(storage.records.isEmpty)
        #expect(retained == nil)
    }

    @Test func failedSaveIsRetryableWithoutDuplicatingRecords() {
        let storage = FaultingHistoryStorage()
        let record1 = makeRecord1()
        let record2 = makeRecord2()
        let sut = PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        storage.failSave = true
        sut.add(record1)
        sut.add(record2)
        #expect(storage.records.isEmpty)
        storage.failSave = false
        #expect(sut.retryPersistence())
        #expect(sut.allRecords == [record1, record2])
        #expect(storage.records.count == 2)
    }

}

private func makeRecord1() -> CallHistoryRecord {
    return CallHistoryRecordTestFactory().makeRecord(number: 1)
}

private func makeRecord2() -> CallHistoryRecord {
    return CallHistoryRecordTestFactory().makeRecord(number: 2)
}

private final class FaultingHistoryStorage: PropertyListStorage {
    var records: [[String: Any]] = []
    var failLoad = false
    var failDelete = false
    var failSave = false
    var saveCount = 0
    func load() throws -> [[String: Any]] {
        if failLoad { throw CocoaError(.fileReadNoPermission) }
        return records
    }
    func save(_ value: [[String: Any]]) throws {
        if failSave { throw CocoaError(.fileWriteOutOfSpace) }
        records = value; saveCount += 1
    }
    func delete() throws {
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        records = []
    }
}
