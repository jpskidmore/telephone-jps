import Foundation
import Darwin

private func now(_ clock: clockid_t = CLOCK_MONOTONIC_RAW) -> Double {
    var time = timespec()
    clock_gettime(clock, &time)
    return Double(time.tv_sec) * 1_000 + Double(time.tv_nsec) / 1_000_000
}

private func memory() -> [String: UInt64] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? ["physicalFootprintBytes": info.phys_footprint, "residentBytes": info.resident_size] : [:]
}

private func percentiles(_ values: [Double]) -> [String: Any] {
    guard !values.isEmpty else { return ["samples": 0] }
    let sorted = values.sorted()
    return ["p50": sorted[(sorted.count - 1) / 2], "p95": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
            "max": sorted.last!, "samples": sorted.count]
}

private func label(_ raw: String) -> String {
    switch raw {
    case "_$!<Home>!$_": "home"
    case "_$!<Mobile>!$_": "mobile"
    case "sip", "SIP": "sip"
    default: raw
    }
}

private struct Destination: Codable {
    let value: String
    let label: String
}

private struct Fixture: Decodable {
    let first: String
    let last: String
    let organisation: String
    let flags: Int
    let phones: [Destination]
    let emails: [Destination]
    enum CodingKeys: String, CodingKey {
        case first = "First", last = "Last", organisation = "Organization", flags = "ABPersonFlags"
        case phones = "Phone", emails = "Email"
    }
    var displayName: String {
        flags == 1 ? organisation : [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    }
    func contact(identifier: Int) -> Contact {
        Contact(name: displayName,
                phones: phones.map { .init(number: $0.value, label: label($0.label), rawLabel: $0.label) },
                emails: emails.map { .init(address: $0.value, label: label($0.label), rawLabel: $0.label) },
                completionMetadata: .init(identifier: String(identifier), givenName: first, familyName: last,
                                          organisation: organisation, isCompany: flags == 1, displayName: displayName))
    }
}

// This parses only the frozen benchmark corpus's simple forms. Production URI
// parsing/formatting and selected-token ownership are verified in native tests.
private func input(_ text: String) -> (user: String, sipAddress: String, displayName: String) {
    var destination = text
    var name = ""
    if let start = text.range(of: " <", options: .backwards), text.hasSuffix(">") {
        destination = String(text[start.upperBound..<text.index(before: text.endIndex)])
        name = String(text[..<start.lowerBound])
    } else if let start = text.range(of: " (", options: .backwards), text.hasSuffix(")") {
        destination = String(text[..<start.lowerBound])
        name = String(text[start.upperBound..<text.index(before: text.endIndex)])
    }
    let user = destination.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    return (user, destination, name)
}

@main private struct CandidateBenchmark {
    static func main() throws {
        guard CommandLine.arguments.count == 5 else { fatalError("candidate fixtures outputs baseline-metrics result") }
        precondition(Thread.isMainThread)
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixtureURL))
        let outputs = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
        let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) as! [String: Any]
        let before = memory()
        let conversionStart = now(), conversionCPUStart = now(CLOCK_THREAD_CPUTIME_ID)
        let contacts = fixtures.enumerated().map { $0.element.contact(identifier: $0.offset) }
        let conversionMS = now() - conversionStart, conversionCPUMS = now(CLOCK_THREAD_CPUTIME_ID) - conversionCPUStart
        let snapshotStart = now(), snapshotCPUStart = now(CLOCK_THREAD_CPUTIME_ID)
        let snapshot = ContactCompletionSnapshot(contacts: contacts)
        let snapshotMS = now() - snapshotStart, snapshotCPUMS = now(CLOCK_THREAD_CPUTIME_ID) - snapshotCPUStart
        let after = memory()
        let expectedCompletions = outputs["completions"] as! [String: [String]]
        var queries: [[String: Any]] = [], allWall: [Double] = [], allCPU: [Double] = []
        var parityFailures: [[String: Any]] = []
        for item in baseline["queryCorpus"] as! [[String: Any]] {
            let query = item["query"] as! String
            let expected = expectedCompletions[query]!
            var wall: [Double] = [], cpu: [Double] = []
            var first = 0.0
            for trial in 0..<7 { autoreleasepool {
                let start = now(), startCPU = now(CLOCK_THREAD_CPUTIME_ID)
                let actual = snapshot.completionStrings(for: query)
                let elapsed = now() - start, elapsedCPU = now(CLOCK_THREAD_CPUTIME_ID) - startCPU
                if actual != expected && trial == 0 {
                    let mismatch = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                    parityFailures.append(["query": query, "expectedCount": expected.count, "actualCount": actual.count,
                                           "firstMismatch": mismatch ?? min(actual.count, expected.count),
                                           "expectedFirst": Array(expected.prefix(8)), "actualFirst": Array(actual.prefix(8))])
                }
                if trial == 0 { first = elapsed }
                if trial >= 2 { wall.append(elapsed); cpu.append(elapsedCPU); allWall.append(elapsed); allCPU.append(elapsedCPU) }
            }}
            queries.append(["query": query, "outputCount": expected.count, "firstCallbackWallMS": first,
                            "wallMS": percentiles(wall), "mainThreadCPUMS": percentiles(cpu)])
        }
        var tokens: [[String: Any]] = [], allTokenWall: [Double] = [], allTokenCPU: [Double] = []
        var matchedTokenCases = 0
        for expected in outputs["tokens"] as! [[String: Any]] {
            let editingString = expected["editingString"] as! String
            let parsed = input(editingString)
            let destinations = expected["destinations"] as! [[String: String]]
            let expectedIdentifier: String?
            if destinations.count > 1, let phone = destinations.first?["user"] {
                expectedIdentifier = fixtures.firstIndex { $0.phones.first?.value == phone }.map(String.init)
            } else { expectedIdentifier = nil }
            var wall: [Double] = [], cpu: [Double] = []
            for trial in 0..<7 { autoreleasepool {
                let start = now(), startCPU = now(CLOCK_THREAD_CPUTIME_ID)
                let contact = snapshot.firstContact(user: parsed.user, sipAddress: parsed.sipAddress, displayName: parsed.displayName)
                let elapsed = now() - start, elapsedCPU = now(CLOCK_THREAD_CPUTIME_ID) - startCPU
                if trial == 0 {
                    if contact?.completionMetadata?.identifier != expectedIdentifier {
                        parityFailures.append(["token": editingString, "expectedIdentifier": expectedIdentifier ?? "nil",
                                               "actualIdentifier": contact?.completionMetadata?.identifier ?? "nil"])
                    } else if let contact {
                        let addresses = contact.phones.map { ($0.number, $0.label) } + contact.emails.filter {
                            ($0.rawLabel ?? "").caseInsensitiveCompare("sip") == .orderedSame
                        }.map { ($0.address, "sip") }
                        let actual = addresses.map { address, label in
                            let parts = address.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
                            return ["user": String(parts[0]), "host": parts.count > 1 ? String(parts[1]) : "",
                                    "name": contact.completionMetadata!.displayName, "label": label]
                        }
                        if actual != destinations { parityFailures.append(["token": editingString, "reason": "Ordered token destinations/name/labels differ"]) }
                    }
                    matchedTokenCases += 1
                }
                if trial >= 2 { wall.append(elapsed); cpu.append(elapsedCPU); allTokenWall.append(elapsed); allTokenCPU.append(elapsedCPU) }
            }}
            tokens.append(["editingString": editingString, "lookupOnlyWallMS": percentiles(wall), "mainThreadLookupCPUMS": percentiles(cpu)])
        }
        let result: [String: Any] = [
            "scope": "Actual pure ContactCompletionSnapshot over the complete frozen synthetic fixture; no Contacts/AddressBook modules, app/profile or provider.",
            "contacts": fixtures.count, "mainThread": Thread.isMainThread,
            "fixtureConversionMS": conversionMS, "fixtureConversionCPUMS": conversionCPUMS,
            "coldSnapshotConstructionMS": snapshotMS, "coldSnapshotConstructionCPUMS": snapshotCPUMS,
            "memoryBeforeContactConversion": before, "memoryAfterSnapshotConstruction": after, "memoryAfterQueries": memory(),
            "completionInputsCompared": queries.count, "tokenInputsCompared": matchedTokenCases,
            "fullOrderedCompletionArraysEqual": parityFailures.isEmpty, "parityFailures": parityFailures,
            "queryCorpus": queries, "aggregateQueryWallMS": percentiles(allWall), "aggregateMainThreadQueryCPUMS": percentiles(allCPU),
            "tokenCorpus": tokens, "aggregateTokenLookupOnlyWallMS": percentiles(allTokenWall),
            "aggregateTokenLookupOnlyCPUMS": percentiles(allTokenCPU),
            "tokenTimingLimit": "Pure firstContact lookup only, excluding formatter, URI creation and native token ownership. Do not compare as full callback speedup.",
            "warmupTrialsPerInput": 2, "measuredTrialsPerInput": 5
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[4]))
        print("contacts=\(fixtures.count) full completion inputs=\(queries.count) token inputs=\(matchedTokenCases) parity failures=\(parityFailures.count)")
        if !parityFailures.isEmpty { exit(78) }
    }
}
