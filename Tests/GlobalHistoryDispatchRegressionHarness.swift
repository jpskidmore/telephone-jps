import Foundation
import UseCases

@main
struct GlobalHistoryDispatchRegressionHarness {
    static func main() async throws { try await verify() }

    @CallHistoryActor
    private static func verify() throws {
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("jps-global-history-dispatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.plist"), secondURL = directory.appendingPathComponent("second.plist")
        let firstStorage = SimplePropertyListStorage(url: firstURL, manager: .default)
        let secondStorage = SimplePropertyListStorage(url: secondURL, manager: .default)
        let literals = ["999", "112", "*21*123#", "12P34"]
        let first = PersistentCallHistory(origin: TruncatingCallHistory(), storage: firstStorage)
        for (index, literal) in literals.enumerated() {
            let record = CallHistoryRecord(uri: URI(user: literal, host: "historical-provider.invalid", displayName: ""),
                                           date: Date(timeIntervalSinceReferenceDate: Double(index)), duration: 1,
                                           isIncoming: false, isMissed: false, canonicalDestination: literal,
                                           originAccountUUID: "a", originAccountName: "First provider")
            first.add(record.removingHost())
        }
        let original = try Data(contentsOf: firstURL)
        let reopened = PersistentCallHistory(origin: TruncatingCallHistory(), storage: firstStorage)
        try require(reopened.persistenceError == nil, "Valid literal metadata must load")
        try require(reopened.allRecords.map(\.callbackDestination) == literals, "Dispatch literals must survive a real file reload")
        try require(try Data(contentsOf: firstURL) == original, "Reopening must not rewrite bytes")
        try original.write(to: secondURL)
        let second = PersistentCallHistory(origin: TruncatingCallHistory(), storage: secondStorage)
        let global = GlobalCallHistory(histories: DispatchHistoryStores(first: reopened, second: second))
        global.updateAccounts([CallHistoryAccount(uuid: "a", name: "First provider", domain: "one"),
                               CallHistoryAccount(uuid: "b", name: "Second provider", domain: "two")])
        try require(global.allRecords.count == 8 && Set(global.allRecords.map(\.identifier)).count == 8,
                    "Equal literal calls in separate account stores must have qualified identities")
        try require(try Data(contentsOf: firstURL) == original && Data(contentsOf: secondURL) == original,
                    "Global projection must not migrate either file")

        let legacy: [String: Any] = ["user": "123456", "host": "", "name": "", "date": Date(timeIntervalSinceReferenceDate: 1),
                                     "duration": 2, "incoming": true, "missed": true]
        let legacyRows = literals.enumerated().map { index, literal -> [String: Any] in
            var row = legacy; row["user"] = literal; row["host"] = "historical-provider.invalid"
            row["date"] = Date(timeIntervalSinceReferenceDate: Double(index)); return row
        }
        try firstStorage.save(legacyRows); let legacyBytes = try Data(contentsOf: firstURL)
        let legacyHistory = PersistentCallHistory(origin: TruncatingCallHistory(), storage: firstStorage)
        try require(legacyHistory.allRecords.map(\.callbackDestination) == literals,
                    "Legacy literals must re-enter routing without a historical provider host")
        try require(legacyHistory.allRecords.allSatisfy { $0.canonicalDestination == nil },
                    "Legacy callback fallback must not invent persisted metadata")
        try require(try Data(contentsOf: firstURL) == legacyBytes, "Legacy callback fallback must not rewrite bytes")
        let validators = literals + ["+441442123456", "sip:desk@example.test:5071;transport=tls", "sip:desk@[2001:db8::1]:5071;transport=tcp"]
        for destination in validators {
            var row = legacy; row["canonicalDestination"] = destination
            try firstStorage.save([row])
            let decoded = try firstStorage.load().first?["canonicalDestination"] as? String
            try require(decoded == destination, "Accepted destinations must retain their exact literal")
        }
        let malformed = ["999\n", "*21*123#\t", "12P\u{0000}34", String(repeating: "1", count: 65), "+abc", "sip:desk@example:NaN"]
        for destination in malformed {
            var row = legacy; row["canonicalDestination"] = destination
            try firstStorage.save([row]); let bytes = try Data(contentsOf: firstURL)
            var rejected = false
            do { _ = try firstStorage.load() } catch { rejected = true }
            try require(rejected, "Malformed destination must fail its read")
            try require(try Data(contentsOf: firstURL) == bytes, "Failed reads must leave bytes intact")
        }
        print("Global history dispatch regressions passed: four emergency/short/service literals survive actual persistence and merged UUID projection; four legacy hosted-user literals route without provider hosts or rewritten metadata; seven valid destinations round-trip, six malformed destinations fail without rewriting bytes.")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "GlobalHistoryDispatchRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}

@CallHistoryActor private final class DispatchHistoryStores: CallHistories {
    private let first: CallHistory, second: CallHistory
    init(first: CallHistory, second: CallHistory) { self.first = first; self.second = second }
    func history(withUUID uuid: String) -> CallHistory { uuid == "a" ? first : second }
    func remove(withUUID uuid: String) {}
}
