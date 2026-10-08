//
//  PersistentCallHistory.swift
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

public let callHistoryPersistenceDidFailNotification = Notification.Name("AKCallHistoryPersistenceDidFailNotification")

@CallHistoryActor
public final class PersistentCallHistory {
    private final class WeakHistory {
        weak var value: PersistentCallHistory?
        // A removed account has no cache owner. Retain only its outstanding
        // durable deletion until retry commits, without permitting new writes.
        var retainedForDeletion: PersistentCallHistory?
        init(_ value: PersistentCallHistory) { self.value = value }
    }
    private static var failedHistories: [WeakHistory] = []
    public static func retryFailedWrites() -> Bool {
        failedHistories.removeAll { $0.value == nil }
        for history in failedHistories.compactMap({ $0.value }) { _ = history.retryPersistence() }
        failedHistories.removeAll { $0.value?.persistenceError == nil }
        return failedHistories.isEmpty
    }

    private let origin: CallHistory
    private let storage: PropertyListStorage
    private var loaded = false
    private var valid = true
    private var failedClear = false
    private var performingMutation = false
    private var target: CallHistoryEventTarget?
    private var pending: [Mutation] = []
    public private(set) var persistenceError: String?

    private enum Mutation {
        case add(CallHistoryRecord), remove(CallHistoryRecord)
    }

    public init(origin: CallHistory, storage: PropertyListStorage) {
        precondition(origin.allRecords.isEmpty)
        self.origin = origin
        self.storage = storage
        _ = load()
    }

    @discardableResult private func load() -> Bool {
        do {
            let records = try storage.load().map(CallHistoryRecord.init(dictionary:))
            origin.removeAll()
            records.forEach(origin.add)
            loaded = true
            for mutation in pending { apply(mutation) }
            clearFailure()
            return true
        } catch {
            fail("read", error)
            return false
        }
    }

    private func apply(_ mutation: Mutation) {
        switch mutation {
        case .add(let record): origin.add(record)
        case .remove(let record): origin.remove(record)
        }
    }

    private func fail(_ operation: String, _ error: Error) {
        persistenceError = error.localizedDescription
        Self.failedHistories.removeAll { $0.value == nil }
        if !Self.failedHistories.contains(where: { $0.value === self }) {
            Self.failedHistories.append(WeakHistory(self))
        }
        let info: [String: Any] = ["operation": operation, "error": error as NSError]
        // Delivery outlives individual windows and never blocks the history actor.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: callHistoryPersistenceDidFailNotification, object: nil, userInfo: info)
        }
    }

    private func clearFailure() {
        persistenceError = nil
        for entry in Self.failedHistories where entry.value === self { entry.retainedForDeletion = nil }
    }
}

extension PersistentCallHistory: CallHistory {
    public var allRecords: [CallHistoryRecord] { origin.allRecords }

    public func add(_ record: CallHistoryRecord) { mutate(.add(record)) }
    public func remove(_ record: CallHistoryRecord) { mutate(.remove(record)) }

    private func mutate(_ mutation: Mutation) {
        guard valid else { return }
        performingMutation = true
        defer { performingMutation = false }
        failedClear = false
        pending.append(mutation)
        if loaded { apply(mutation) }
        // A failed initial read must never be mistaken for an empty history.
        _ = retryPersistence()
    }

    public func removeAll() {
        guard valid else { return }
        _ = clearHistory()
    }

    @discardableResult private func clearHistory() -> Bool {
        do {
            // Commit durable deletion before showing an empty history.
            try storage.delete()
            origin.removeAll()
            failedClear = false
            pending.removeAll()
            loaded = true
            clearFailure()
            return true
        } catch {
            failedClear = true
            fail("clear", error)
            return false
        }
    }

    public func invalidate() {
        valid = false
        if failedClear {
            for entry in Self.failedHistories where entry.value === self { entry.retainedForDeletion = self }
        } else {
            pending.removeAll()
            clearFailure()
        }
    }

    @discardableResult public func retryPersistence() -> Bool {
        let recovering = persistenceError != nil
        let succeeded = persistPending()
        if recovering && succeeded && !performingMutation { target?.didUpdate(self) }
        return succeeded
    }

    private func persistPending() -> Bool {
        // Removal invalidates additions immediately, but the deletion already
        // requested must remain retryable after its cache owner disappears.
        if failedClear { return clearHistory() }
        guard valid else { return true }
        if !loaded && !load() { return false }
        guard !pending.isEmpty else { return persistenceError == nil }
        do {
            try storage.save(dictionaries(from: origin.allRecords))
            pending.removeAll()
            clearFailure()
            return true
        } catch {
            fail("save", error)
            return false
        }
    }

    public func updateTarget(_ target: CallHistoryEventTarget) { self.target = target; origin.updateTarget(target) }
}

private extension CallHistoryRecord {
    init(dictionary: [String: Any]) {
        self.init(
            uri: URI(
                user: dictionary[Keys.user.rawValue] as? String ?? "",
                address: ServiceAddress(host: dictionary[Keys.host.rawValue] as? String ?? "",
                                        port: dictionary[Keys.port.rawValue] as? String ?? ""),
                displayName: dictionary[Keys.name.rawValue] as? String ?? "",
                transport: historyTransport(from: dictionary[Keys.transport.rawValue] as? String)
            ),
            date: dictionary[Keys.date.rawValue] as? Date ?? Date.distantPast,
            duration: dictionary[Keys.duration.rawValue] as? Int ?? 0,
            isIncoming: dictionary[Keys.incoming.rawValue] as? Bool ?? false,
            isMissed: dictionary[Keys.missed.rawValue] as? Bool ?? false,
            canonicalDestination: dictionary[Keys.canonicalDestination.rawValue] as? String,
            originAccountUUID: dictionary[Keys.originAccountUUID.rawValue] as? String,
            originAccountName: dictionary[Keys.originAccountName.rawValue] as? String
        )
    }
}

private func dictionaries(from records: [CallHistoryRecord]) -> [[String: Any]] {
    return records.map {
        var result: [String: Any] = [
            Keys.user.rawValue: $0.uri.user,
            Keys.host.rawValue: $0.uri.host,
            Keys.name.rawValue: $0.uri.displayName,
            Keys.date.rawValue: $0.date,
            Keys.duration.rawValue: $0.duration,
            Keys.incoming.rawValue: $0.isIncoming,
            Keys.missed.rawValue: $0.isMissed
        ]
        if !$0.uri.port.isEmpty { result[Keys.port.rawValue] = $0.uri.port }
        if $0.uri.transport != .udp { result[Keys.transport.rawValue] = $0.uri.transport.stringValue }
        if let value = $0.canonicalDestination { result[Keys.canonicalDestination.rawValue] = value }
        if let value = $0.originAccountUUID { result[Keys.originAccountUUID.rawValue] = value }
        if let value = $0.originAccountName { result[Keys.originAccountName.rawValue] = value }
        return result
    }
}

private enum Keys: String {
    case user, host, name, date, duration, incoming, missed
    case port, transport, canonicalDestination, originAccountUUID, originAccountName
}

private func historyTransport(from value: String?) -> Transport {
    switch value {
    case "tcp": .tcp
    case "tls": .tls
    default: .udp
    }
}
