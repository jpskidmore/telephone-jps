// A merged view over the existing UUID stores. Reading does not migrate or rewrite saved history.
import Foundation

@objc public final class CallHistoryAccount: NSObject, Sendable {
    @objc public let uuid: String
    @objc public let name: String
    @objc public let domain: String

    @objc(initWithUUID:name:domain:)
    public init(uuid: String, name: String, domain: String) {
        self.uuid = uuid
        self.name = name
        self.domain = domain
    }
}

/// Names are presentation metadata. UUIDs alone select a store, including after a rename or reorder.
public final class CallHistoryAccountCatalog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String: String] = [:]
    public init() {}
    public func update(_ accounts: [CallHistoryAccount]) {
        lock.lock(); defer { lock.unlock() }
        names = accounts.reduce(into: [:]) { $0[$1.uuid] = $1.name }
    }
    public func name(forUUID uuid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return names[uuid]
    }
}

@CallHistoryActor
public final class GlobalCallHistory: CallHistory {
    private let histories: CallHistories
    private var accounts: [CallHistoryAccount] = []
    private var stores: [String: CallHistory] = [:]
    private var target: CallHistoryEventTarget?

    public nonisolated init(histories: CallHistories) { self.histories = histories }

    public func updateAccounts(_ accounts: [CallHistoryAccount], request: CallHistoryReloadRequest? = nil) {
        guard request?.isCurrent != false else { return }
        var seen = Set<String>()
        self.accounts = accounts.filter { !$0.uuid.isEmpty && seen.insert($0.uuid).inserted }
        let uuids = Set(self.accounts.map(\.uuid))
        stores = stores.filter { uuids.contains($0.key) }
        for account in self.accounts {
            let history = histories.history(withUUID: account.uuid)
            stores[account.uuid] = history
            // The global target replaces the former per-account window subscription.
            history.updateTarget(WeakCallHistoryEventTarget(origin: self))
        }
        target?.didUpdate(self)
    }

    public var allRecords: [CallHistoryRecord] {
        accounts.flatMap { account in
            (stores[account.uuid]?.allRecords ?? []).map { $0.qualified(accountUUID: account.uuid, accountName: account.name) }
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            // Deterministic equal-time order avoids selection jumps on a settings refresh.
            return $0.identifier < $1.identifier
        }
    }

    public func add(_ record: CallHistoryRecord) {
        // Calls continue logging through the original per-account histories, never through this projection.
    }

    public func remove(_ record: CallHistoryRecord) {
        guard let uuid = record.originAccountUUID, let store = stores[uuid],
              let original = store.record(withIdentifier: record.accountRecordIdentifier) else { return }
        store.remove(original)
    }

    public func removeAll() {
        // Each durable store retains its own transactional-clear/retry behaviour.
        for account in accounts { stores[account.uuid]?.removeAll() }
    }

    public func updateTarget(_ target: CallHistoryEventTarget) { self.target = target }
    public var persistenceError: String? {
        accounts.compactMap { stores[$0.uuid]?.persistenceError }.first
    }
    @discardableResult public func retryPersistence() -> Bool {
        var succeeded = true
        for account in accounts {
            if stores[account.uuid]?.retryPersistence() == false { succeeded = false }
        }
        return succeeded
    }
}

extension GlobalCallHistory: CallHistoryEventTarget {
    public nonisolated func didUpdate(_ history: CallHistory) {
        Task { @CallHistoryActor [weak self] in
            guard let self else { return }
            self.target?.didUpdate(self)
        }
    }
}
