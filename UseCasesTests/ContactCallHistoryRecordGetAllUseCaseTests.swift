//
//  ContactCallHistoryRecordGetAllUseCaseTests.swift
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
import UseCases
import UseCasesTestDoubles

@ContactsActor
struct ContactCallHistoryRecordGetAllUseCaseTests {
    @Test func callsUpdateOnOutputWithRecordsConvertedUsingMatchedContactFactoryOnUpdate() async {
        let record1 = CallHistoryRecordTestFactory().makeRecord(number: 1)
        let record2 = CallHistoryRecordTestFactory().makeRecord(number: 2)
        let contact1 = MatchedContact(uri: record1.uri)
        let contact2 = MatchedContact(uri: record2.uri)
        let output = ContactCallHistoryRecordGetAllUseCaseOutputSpy()
        let sut = ContactCallHistoryRecordGetAllUseCase(
            factory: FallingBackMatchedContactFactory(
                matching: ContactMatchingStub([record1.uri: contact1, record2.uri: contact2])
            ),
            output: output
        )

        await sut.update(records: [record1, record2])

        #expect(
            output.invokedRecords ==
            [
                ContactCallHistoryRecord(origin: record1, contact: contact1),
                ContactCallHistoryRecord(origin: record2, contact: contact2)
            ]
        )
    }
    @Test func discardsOlderSnapshotAfterClearCompletesThroughContacts() async {
        let generation = CallHistoryReloadGeneration()
        let matching = SuspendedHistoryContactMatching()
        let output = HistorySnapshotsOutput()
        let sut = ContactCallHistoryRecordGetAllUseCase(factory: FallingBackMatchedContactFactory(matching: matching), output: output)
        let oldRequest = generation.next()
        let old = Task {
            await sut.update(records: [CallHistoryRecordTestFactory().makeRecord(number: 1)], request: oldRequest)
        }
        while !matching.entered { await Task.yield() }
        let clearRequest = generation.next()
        await sut.update(records: [], request: clearRequest)
        matching.release()
        await old.value
        #expect(output.snapshots.count == 1)
        #expect(output.snapshots[0].isEmpty)
    }

    @Test func discardsOlderNonemptySnapshotWhenNewerRefreshFinishesFirst() async {
        let generation = CallHistoryReloadGeneration()
        let matching = SuspendedHistoryContactMatching()
        let output = HistorySnapshotsOutput()
        let sut = ContactCallHistoryRecordGetAllUseCase(factory: FallingBackMatchedContactFactory(matching: matching), output: output)
        let first = generation.next()
        let old = Task { await sut.update(records: [CallHistoryRecordTestFactory().makeRecord(number: 1)], request: first) }
        while !matching.entered { await Task.yield() }
        let newer = generation.next()
        let latest = CallHistoryRecordTestFactory().makeRecord(number: 2)
        await sut.update(records: [latest], request: newer)
        matching.release()
        await old.value
        #expect(output.snapshots.count == 1)
        #expect(output.snapshots[0].map(\.origin) == [latest])
    }

}

@ContactsActor private final class SuspendedHistoryContactMatching: ContactMatching {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func match(for uri: URI) async -> MatchedContact? {
        if !entered {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }
        return nil
    }
    func release() { continuation?.resume(); continuation = nil }
}
@ContactsActor private final class HistorySnapshotsOutput: ContactCallHistoryRecordGetAllUseCaseOutput {
    var snapshots: [[ContactCallHistoryRecord]] = []
    func update(records: [ContactCallHistoryRecord]) async { snapshots.append(records) }
}
