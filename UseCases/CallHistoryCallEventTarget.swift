//
//  CallHistoryCallEventTarget.swift
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

// Admission happens synchronously, before the first actor hop, so Quit can wait
// for queued writes as well as writes already running. Nested admitted writes
// remain admitted while the top-level shutdown gate is closed.
public final class CallHistoryWork: @unchecked Sendable {
    public static let shared = CallHistoryWork()
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var accepting = true
    @TaskLocal private static var admitted = false

    public init() {}
    @discardableResult public func submit(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        lock.lock()
        guard accepting || Self.admitted else { lock.unlock(); return false }
        group.enter()
        lock.unlock()
        Task {
            await Self.$admitted.withValue(true) { await operation() }
            group.leave()
        }
        return true
    }

    public func finish(completion: @escaping @Sendable () -> Void) {
        lock.lock()
        accepting = false
        lock.unlock()
        group.notify(queue: .main, execute: completion)
    }
    public func resume() { lock.lock(); accepting = true; lock.unlock() }
}

public final class CallHistoryCallEventTarget: @unchecked Sendable {
    private let histories: CallHistories
    private let factory: CallHistoryRecordAddUseCaseFactory
    private let accountName: @Sendable (String) -> String?
    private let namesLock = NSLock()
    private var callNames: [ObjectIdentifier: String] = [:]

    public init(histories: CallHistories, factory: CallHistoryRecordAddUseCaseFactory,
                accountName: @escaping @Sendable (String) -> String? = { _ in nil }) {
        self.histories = histories
        self.factory = factory
        self.accountName = accountName
    }
}

extension CallHistoryCallEventTarget: CallEventTarget {
    public func didDisconnect(_ call: Call) {
        let uuid = call.account.uuid
        let domain = call.account.domain
        namesLock.lock()
        let capturedName = callNames.removeValue(forKey: ObjectIdentifier(call))
        namesLock.unlock()
        // Read the call-time canonical value at disconnection: the incoming
        // notification may assign it after this target's receive observer.
        let record = CallHistoryRecord(call: call, originAccountName: capturedName ?? accountName(uuid))
        CallHistoryWork.shared.submit { [histories, factory] in
            factory.make(
                history: await histories.history(withUUID: uuid),
                record: record,
                domain: domain
            ).execute()
        }
    }

    public func didMake(_ call: Call) { captureName(call) }
    public func didReceive(_ call: Call) { captureName(call) }
    public func isConnecting(_ call: Call) {}

    private func captureName(_ call: Call) {
        guard let name = accountName(call.account.uuid) else { return }
        namesLock.lock(); defer { namesLock.unlock() }
        callNames[ObjectIdentifier(call)] = name
    }
}
