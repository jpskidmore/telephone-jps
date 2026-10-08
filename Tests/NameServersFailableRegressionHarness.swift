import Foundation

private final class InertDNSChangeTarget: NSObject, NameServersChangeEventTarget {
    func nameServersDidChange(_ source: NameServers) {}
}
@main private struct DNSFailableRegression {
    static func main() {
        for step in 0...3 {
            TestSetResourceFailure(Int32(step))
            autoreleasepool {
                let result = NameServers(bundle: .main, target: InertDNSChangeTarget())
                precondition((result != nil) == (step == 3))
                if let result { precondition(result.all.isEmpty) }
            }
        }
        print("DNS Swift nullable-initializer regressions passed: failed creation/import safely returns nil")
    }
}
