//
//  CallHistoryCallEventTargetTests.swift
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

import UseCases
import UseCasesTestDoubles
import XCTest

final class CallHistoryCallEventTargetTests: XCTestCase {
    func testIncomingObserverOrderPreservesReceiptTimeCanonicalAndCallTimeAccountName() {
        let catalog = CallHistoryAccountCatalog()
        catalog.update([CallHistoryAccount(uuid: "origin", name: "First provider", domain: "provider")])
        let recorded = expectation(description: "Call metadata logged")
        var result: CallHistoryRecord?
        let history = TruncatingCallHistory()
        let sut = CallHistoryCallEventTarget(
            histories: DefaultCallHistories(factory: CallHistoryFactorySpy(history: history)),
            factory: CallHistoryRecordAddUseCaseFactorySpy(add: UseCaseSpy(), makeCallback: { _, record, _ in
                result = record; recorded.fulfill()
            }),
            accountName: { catalog.name(forUUID: $0) }
        )
        let call = CanonicalHistoryCall()
        sut.didReceive(call)
        // Root incoming delivery captures the canonical number after an earlier
        // history observer; a later profile or account-name edit cannot change it.
        call.canonicalDestination = "+441442123456"
        catalog.update([CallHistoryAccount(uuid: "origin", name: "Renamed later", domain: "provider")])
        sut.didDisconnect(call)
        wait(for: [recorded], timeout: 1)
        XCTAssertEqual(result?.canonicalDestination, "+441442123456")
        XCTAssertEqual(result?.originAccountUUID, "origin")
        XCTAssertEqual(result?.originAccountName, "First provider")
        XCTAssertEqual(result?.uri.user, "123456")
    }
    func testCreatesUseCaseWithExpectedArgumentsOnDidDisconnect() {
        let account = SimpleAccount(uuid: "any-id", domain: "any-domain")
        let history: CallHistory = TruncatingCallHistory()
        let didCallMake = expectation(description: "Calls make on factory")
        var invokedHistory: CallHistory?
        var invokedRecord: CallHistoryRecord?
        var invokedDomain: String?
        let factory = CallHistoryRecordAddUseCaseFactorySpy(
            add: UseCaseSpy(),
            makeCallback: { history, record, domain in
                invokedHistory = history
                invokedRecord = record
                invokedDomain = domain
                didCallMake.fulfill()
            }
        )
        let sut = CallHistoryCallEventTarget(
            histories: DefaultCallHistories(factory: CallHistoryFactorySpy(history: history)), factory: factory
        )
        let call = makeCall(account: account)

        sut.didDisconnect(call)

        wait(for: [didCallMake], timeout: 1)
        XCTAssertTrue(invokedHistory === history)
        XCTAssertEqual(invokedRecord, CallHistoryRecord(call: call))
        XCTAssertEqual(invokedDomain, account.domain)
    }

    func testExecutesUseCaseOnDidDisconnect() {
        let histories = DefaultCallHistories(factory: CallHistoryFactorySpy(history: TruncatingCallHistory()))
        let didCallExecute = expectation(description: "Calls execute on add")
        let sut = CallHistoryCallEventTarget(
            histories: histories,
            factory: CallHistoryRecordAddUseCaseFactorySpy(
                add: UseCaseSpy(callBack: didCallExecute.fulfill), makeCallback: { _, _, _ in }
            )
        )
        let call = makeCall(account: SimpleAccount(uuid: "any-id", domain: "any-domain"))

        sut.didDisconnect(call)

        wait(for: [didCallExecute], timeout: 1)
    }
    func testDrainWaitsForQueuedAndNestedWritesBeforeFinalCompletion() async {
        let coordinator = CallHistoryWork()
        let first = HistoryWorkLatch()
        let nested = HistoryWorkLatch()
        let drained = expectation(description: "All admitted writes are durable")
        let finished = HistoryWorkFlag()
        XCTAssertTrue(coordinator.submit {
            await first.wait()
            coordinator.submit { await nested.wait() }
        })
        while !(await first.entered) { await Task.yield() }
        coordinator.finish { finished.set(); drained.fulfill() }
        XCTAssertFalse(finished.value)
        XCTAssertFalse(coordinator.submit {})
        await first.release()
        while !(await nested.entered) { await Task.yield() }
        XCTAssertFalse(finished.value)
        await nested.release()
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertTrue(finished.value)
        coordinator.resume()
        XCTAssertTrue(coordinator.submit {})
    }

}

private final class CanonicalHistoryCall: NSObject, Call, @unchecked Sendable {
    let account: Account = SimpleAccount(uuid: "origin", domain: "provider")
    let remote = URI(user: "123456", host: "provider", displayName: "")
    let date = Date(timeIntervalSinceReferenceDate: 10)
    let duration = 2
    let isIncoming = true
    let isMissed = false
    var canonicalDestination: String?
}

private func makeCall(account: Account) -> Call {
    return SimpleCall(
        account: account,
        remote: URI(user: "any-user", host: "any-host", displayName: "any-name"),
        date: Date(),
        duration: 60,
        isIncoming: false,
        isMissed: false
    )
}

private actor HistoryWorkLatch {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private final class HistoryWorkFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}
