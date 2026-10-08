import Foundation
import UseCases

@CallHistoryActor private final class ScratchHistoryFactory: CallHistoryFactory {
    let root: URL
    nonisolated init(root: URL) { self.root = root }
    func make(uuid: String) -> CallHistory {
        PersistentCallHistory(origin: TruncatingCallHistory(), storage: SimplePropertyListStorage(
            url: root.appendingPathComponent(uuid + ".plist"), manager: .default))
    }
}

private func record(_ number: Int) -> CallHistoryRecord {
    CallHistoryRecord(uri: URI(user: "synthetic-\(number)", host: "audit.invalid", displayName: "Test"),
                      date: Date(timeIntervalSince1970: Double(number)), duration: number,
                      isIncoming: false, isMissed: false)
}
private func require(_ condition: Bool, _ description: String) throws {
    if !condition { throw NSError(domain: "HistoryRegression", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: description]) }
}
private func drain() async {
    await withCheckedContinuation { continuation in
        CallHistoryWork.shared.finish { continuation.resume() }
    }
    CallHistoryWork.shared.resume()
}

@main private struct HistoryRegression {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("telephone-history-regression-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        defer {
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? manager.removeItem(at: root)
        }
        let url = root.appendingPathComponent("read-failure.plist")
        let storage = SimplePropertyListStorage(url: url, manager: manager)
        let seed = await PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        await seed.add(record(1)); await seed.add(record(2))
        let original = try Data(contentsOf: url)
        try manager.setAttributes([.posixPermissions: 0o200], ofItemAtPath: url.path)
        let failed = await PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        await failed.add(record(3))
        try require(await failed.persistenceError != nil, "Unreadable file must surface failure")
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try require(try Data(contentsOf: url) == original, "Failed load followed by add must preserve exact original bytes")
        try require(await failed.retryPersistence(), "Restored permissions must allow retry")
        let reloaded = await PersistentCallHistory(origin: TruncatingCallHistory(), storage: storage)
        try require(await reloaded.allRecords == [record(1), record(2), record(3)], "Recovery must merge previous and queued records")

        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        await reloaded.removeAll()
        try require(await reloaded.allRecords.count == 3, "Failed durable clear must retain visible records")
        try require(manager.fileExists(atPath: url.path), "Failed clear must not claim deletion")
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try require(await reloaded.retryPersistence(), "A clear retry must commit the deletion")
        try require(!manager.fileExists(atPath: url.path), "Successful clear must remain absent on disk")

        let malformed = root.appendingPathComponent("malformed.plist")
        let malformedBytes = try PropertyListSerialization.data(fromPropertyList: ["bad": "shape"], format: .binary, options: 0)
        try malformedBytes.write(to: malformed)
        let malformedStorage = SimplePropertyListStorage(url: malformed, manager: manager)
        let malformedHistory = await PersistentCallHistory(origin: TruncatingCallHistory(), storage: malformedStorage)
        await malformedHistory.add(record(4))
        try require(try Data(contentsOf: malformed) == malformedBytes, "Malformed existing data must never be replaced")
        let missingStorage = SimplePropertyListStorage(url: root.appendingPathComponent("missing.plist"), manager: manager)
        try require(try missingStorage.load().isEmpty, "Genuinely absent history must initialise empty")

        let histories = DefaultCallHistories(factory: ScratchHistoryFactory(root: root))
        let held = await histories.history(withUUID: "deleted-account")
        await held.add(record(5))
        let delayedAdd = CallHistoryRecordAddUseCase(history: held, record: record(6), domain: "audit.invalid")
        CallHistoriesHistoryRemoveUseCase(histories: histories).didRemoveAccount(withUUID: "deleted-account")
        await drain()
        let deletedURL = root.appendingPathComponent("deleted-account.plist")
        try require(!manager.fileExists(atPath: deletedURL.path), "Account deletion must remove storage")
        delayedAdd.execute()
        await drain()
        try require(!manager.fileExists(atPath: deletedURL.path), "Held history must reject delayed additions after deletion")
        let retired = await histories.history(withUUID: "deleted-account")
        await retired.add(record(7))
        try require(!manager.fileExists(atPath: deletedURL.path), "Deletion before acquisition must remain tombstoned")
        let newHistory = await histories.history(withUUID: "new-account")
        await newHistory.add(record(8))
        try require(manager.fileExists(atPath: root.appendingPathComponent("new-account.plist").path), "New account UUID must continue persisting")
        print("history filesystem regressions passed: read denial, malformed/absent file, transactional clear and account invalidation")
    }
}
