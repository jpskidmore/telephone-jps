//
//  DefaultCallHistoriesTests.swift
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

import Testing
import Foundation
@testable import UseCases
import UseCasesTestDoubles

@CallHistoryActor
struct DefaultCallHistoriesTests {
    @Test func createsHistoryOnFirstGet() {
        let history = TruncatingCallHistory()
        let sut = DefaultCallHistories(factory: CallHistoryFactorySpy(history: history))

        let result = sut.history(withUUID: "any-uuid")

        #expect(sut.count == 1)
        #expect(result === history)
    }

    @Test func usesExpectedUUIDOnHistoryCreation() {
        let factory = CallHistoryFactorySpy(history: TruncatingCallHistory())
        let sut = DefaultCallHistories(factory: factory)
        let uuid = "any-uuid"

        _ = sut.history(withUUID: uuid)

        #expect(factory.invokedUUID == uuid)
    }

    @Test func removesHistoryOnRemove() {
        let sut = DefaultCallHistories(factory: CallHistoryFactorySpy(history: TruncatingCallHistory()))
        let uuid1 = "uuid1"
        let uuid2 = "uuid2"
        _ = sut.history(withUUID: uuid1)
        _ = sut.history(withUUID: uuid2)

        sut.remove(withUUID: uuid1)
        sut.remove(withUUID: uuid2)

        #expect(sut.count == 0)
    }
    @Test func accountRemovalInvalidatesHeldHistoryAndTombstonesLaterLookups() {
        let origin = TruncatingCallHistory()
        let factory = CallHistoryFactorySpy(history: origin)
        let sut = DefaultCallHistories(factory: factory)
        let held = sut.history(withUUID: "retired")
        held.add(CallHistoryRecordTestFactory().makeRecord(number: 1))
        held.removeAll()
        sut.remove(withUUID: "retired")
        held.add(CallHistoryRecordTestFactory().makeRecord(number: 2))
        #expect(held.allRecords.isEmpty)
        #expect(sut.history(withUUID: "retired").allRecords.isEmpty)
        #expect(sut.count == 0)
    }

}

@CallHistoryActor
struct GlobalCallHistoryTests {
    @Test func mergesEveryConfiguredUUIDAndKeepsEqualAccountRecordsDistinctWithoutWrites() {
        let firstStorage = GlobalHistoryStorage(), secondStorage = GlobalHistoryStorage()
        firstStorage.records = [dictionary(date: 10), dictionary(date: 20)]
        secondStorage.records = [dictionary(date: 10), dictionary(date: 30, incoming: true, missed: true)]
        let first = PersistentCallHistory(origin: TruncatingCallHistory(), storage: firstStorage)
        let second = PersistentCallHistory(origin: TruncatingCallHistory(), storage: secondStorage)
        let sut = GlobalCallHistory(histories: GlobalHistoryMap(stores: ["a": first, "b": second]))
        sut.updateAccounts(accounts())

        let records = sut.allRecords
        #expect(records.count == 4)
        #expect(records.map { $0.date.timeIntervalSinceReferenceDate } == [30, 20, 10, 10])
        #expect(Set(records.map(\.identifier)).count == 4)
        #expect(records[0].originAccountUUID == "b")
        #expect(records[0].isIncoming && records[0].isMissed)
        #expect(firstStorage.saveCount == 0 && secondStorage.saveCount == 0)
        #expect(firstStorage.deleteCount == 0 && secondStorage.deleteCount == 0)
        #expect((firstStorage.records as NSArray).isEqual(firstStorage.initialRecords))
    }

    @Test func renameReorderAndStaleRefreshKeepUUIDIdentityAndLatestNames() {
        let record = CallHistoryRecordTestFactory().makeRecord(number: 1)
        let first = TruncatingCallHistory(), second = TruncatingCallHistory()
        first.add(record); second.add(record)
        let sut = GlobalCallHistory(histories: GlobalHistoryMap(stores: ["a": first, "b": second]))
        sut.updateAccounts(accounts())
        let oldIDs = sut.allRecords.map(\.identifier)
        let generation = CallHistoryReloadGeneration(); let stale = generation.next(); let latest = generation.next()
        sut.updateAccounts([CallHistoryAccount(uuid: "b", name: "Renamed second", domain: "two"),
                            CallHistoryAccount(uuid: "a", name: "Primary", domain: "one")], request: latest)
        sut.updateAccounts(accounts(), request: stale)
        #expect(sut.allRecords.map(\.identifier) == oldIDs)
        #expect(sut.allRecords.map(\.originAccountName) == ["Primary", "Renamed second"])
    }

    @Test func removalTargetsOnlyTheQualifiedOriginAndRemovedConfiguredUUIDNoLongerAppears() {
        let record = CallHistoryRecordTestFactory().makeRecord(number: 1)
        let first = TruncatingCallHistory(), second = TruncatingCallHistory()
        first.add(record); second.add(record)
        let sut = GlobalCallHistory(histories: GlobalHistoryMap(stores: ["a": first, "b": second]))
        sut.updateAccounts(accounts())
        let selected = sut.allRecords.first { $0.originAccountUUID == "b" }!
        sut.remove(selected)
        #expect(first.allRecords == [record]); #expect(second.allRecords.isEmpty)
        sut.updateAccounts([accounts()[1]])
        #expect(sut.record(withIdentifier: "a|\(record.identifier)") == nil)
        sut.remove(selected)
        #expect(first.allRecords == [record])
    }

    @Test func clearFailureRetainsItsOriginalStoreAndRetryOnlyCommitsAfterRecovery() {
        let record = CallHistoryRecordTestFactory().makeRecord(number: 1)
        let firstStorage = GlobalHistoryStorage(), secondStorage = GlobalHistoryStorage()
        let first = PersistentCallHistory(origin: TruncatingCallHistory(), storage: firstStorage)
        let second = PersistentCallHistory(origin: TruncatingCallHistory(), storage: secondStorage)
        first.add(record); second.add(record)
        let sut = GlobalCallHistory(histories: GlobalHistoryMap(stores: ["a": first, "b": second]))
        sut.updateAccounts(accounts()); secondStorage.failDelete = true
        sut.removeAll()
        #expect(first.allRecords.isEmpty)
        #expect(second.allRecords == [record])
        #expect(sut.allRecords.count == 1 && sut.persistenceError != nil)
        #expect(!sut.retryPersistence())
        secondStorage.failDelete = false
        #expect(sut.retryPersistence()); #expect(sut.allRecords.isEmpty)
        #expect(firstStorage.records.isEmpty && secondStorage.records.isEmpty)
    }

    private func accounts() -> [CallHistoryAccount] {
        [CallHistoryAccount(uuid: "a", name: "First provider", domain: "one"),
         CallHistoryAccount(uuid: "b", name: "Second provider", domain: "two")]
    }
    private func dictionary(date: TimeInterval, incoming: Bool = false, missed: Bool = false) -> [String: Any] {
        ["user": "01442123456", "host": "", "name": "", "date": Date(timeIntervalSinceReferenceDate: date),
         "duration": 3, "incoming": incoming, "missed": missed]
    }
}

@CallHistoryActor private final class GlobalHistoryMap: CallHistories {
    let stores: [String: CallHistory]
    init(stores: [String: CallHistory]) { self.stores = stores }
    func history(withUUID uuid: String) -> CallHistory { stores[uuid]! }
    func remove(withUUID uuid: String) { stores[uuid]?.invalidate() }
}
private final class GlobalHistoryStorage: PropertyListStorage {
    var initialRecords: [[String: Any]] = []
    var records: [[String: Any]] = [] { didSet { if initialRecords.isEmpty { initialRecords = records } } }
    var saveCount = 0, deleteCount = 0
    var failDelete = false
    func load() throws -> [[String: Any]] { records }
    func save(_ records: [[String: Any]]) throws { saveCount += 1; self.records = records }
    func delete() throws {
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        deleteCount += 1; records = []
    }
}
