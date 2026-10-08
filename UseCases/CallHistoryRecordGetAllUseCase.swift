//
//  CallHistoryRecordGetAllUseCase.swift
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

public final class CallHistoryReloadGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    public init() {}
    public func next() -> CallHistoryReloadRequest {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        return CallHistoryReloadRequest(owner: self, generation: generation)
    }
    fileprivate func isCurrent(_ value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }
}

public struct CallHistoryReloadRequest: Sendable {
    fileprivate let owner: CallHistoryReloadGeneration
    fileprivate let generation: UInt64
    public var isCurrent: Bool { owner.isCurrent(generation) }
}

public protocol CallHistoryRecordGetAllUseCaseOutput: Sendable {
    func update(records: [CallHistoryRecord]) async
    func update(records: [CallHistoryRecord], request: CallHistoryReloadRequest) async
}
public extension CallHistoryRecordGetAllUseCaseOutput {
    func update(records: [CallHistoryRecord], request: CallHistoryReloadRequest) async {
        guard request.isCurrent else { return }
        await update(records: records)
    }
}

public final class CallHistoryRecordGetAllUseCase: Sendable {
    private let generation = CallHistoryReloadGeneration()
    private let history: CallHistory
    private let output: CallHistoryRecordGetAllUseCaseOutput

    public init(history: CallHistory, output: CallHistoryRecordGetAllUseCaseOutput) {
        self.history = history
        self.output = output
    }
}

extension CallHistoryRecordGetAllUseCase: UseCase {
    public func execute() {
        let request = generation.next()
        Task {
            let records = await history.allRecords
            guard request.isCurrent else { return }
            await output.update(records: records, request: request)
        }
    }
}
