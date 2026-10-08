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
