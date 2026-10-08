import Foundation
import UseCases
import Domain

extension Notification.Name {
    static let AKSIPUserAgentDidFinishStarting = Notification.Name("AKSIPUserAgentDidFinishStarting")
    static let AKSIPUserAgentDidFinishStopping = Notification.Name("AKSIPUserAgentDidFinishStopping")
    static let AKSIPUserAgentDidDetectNAT = Notification.Name("AKSIPUserAgentDidDetectNAT")
    static let AKSIPCallCalling = Notification.Name("AKSIPCallCalling")
    static let AKSIPCallIncoming = Notification.Name("AKSIPCallIncoming")
}
final class ActivityRecorder {
    var begun: [Int] = []
    var ended: [Int] = []
    var released: [Int] = []
    var reasons: [String] = []
    var options: [UInt64] = []
}
final class FakeActivityToken: NSObject {
    let identifier: Int
    let recorder: ActivityRecorder
    init(identifier: Int, recorder: ActivityRecorder) {self.identifier=identifier;self.recorder=recorder}
    deinit {recorder.released.append(identifier)}
}
final class FakeProcessInfo: ProcessInfo, @unchecked Sendable {
    let recorder = ActivityRecorder()
    weak var latest: FakeActivityToken?
    override func beginActivity(options: ProcessInfo.ActivityOptions = [], reason: String) -> any NSObjectProtocol {
        let identifier=recorder.begun.count+1
        recorder.begun.append(identifier);recorder.reasons.append(reason);recorder.options.append(options.rawValue)
        let token=FakeActivityToken(identifier:identifier,recorder:recorder);latest=token
        return token
    }
    override func endActivity(_ activity: any NSObjectProtocol) {
        guard let token=activity as? FakeActivityToken else {fatalError("Only fake tokens are allowed")}
        recorder.ended.append(token.identifier)
    }
}
final class InertUserAgent: NSObject, UserAgent {
    var isStarted=false
    var maxCalls=0
    func start() {fatalError("Starting an agent is forbidden in this audit")}
    func audioDevices() throws -> [UserAgentAudioDevice] {fatalError("Hardware access is forbidden")}
    func updateAudioDevices() {fatalError("Hardware access is forbidden")}
    func selectSoundIODeviceIDs(input: Int, output: Int) throws {fatalError("Hardware access is forbidden")}
}
func describe(_ name:String, _ process:FakeProcessInfo) {
    print("\(name) begun=\(process.recorder.begun) ended=\(process.recorder.ended) released=\(process.recorder.released) latestAlive=\(process.latest?.identifier.description ?? "none")")
}
@main struct ActivityRegression {
    static func main() {
        let process = FakeProcessInfo()
        let agent = InertUserAgent()
        let target = BackgroundActivityUserAgentEventTarget(process: process)
        let source = AKSIPUserAgentEventSource(target: target, agent: agent)
        let center = NotificationCenter.default
        for _ in 0..<3 { center.post(name: .AKSIPUserAgentDidFinishStarting, object: agent) }
        precondition(process.recorder.begun.isEmpty && process.latest == nil)
        agent.isStarted = true
        center.post(name: .AKSIPUserAgentDidFinishStarting, object: agent)
        center.post(name: .AKSIPUserAgentDidFinishStarting, object: agent)
        precondition(process.recorder.begun == [1] && process.recorder.ended.isEmpty)
        agent.isStarted = false
        center.post(name: .AKSIPUserAgentDidFinishStarting, object: agent)
        precondition(process.recorder.ended == [1] && process.latest == nil)
        center.post(name: .AKSIPUserAgentDidFinishStopping, object: agent)
        precondition(process.recorder.ended == [1])
        agent.isStarted = true
        center.post(name: .AKSIPUserAgentDidFinishStarting, object: agent)
        agent.isStarted = false
        center.post(name: .AKSIPUserAgentDidFinishStopping, object: agent)
        center.post(name: .AKSIPUserAgentDidFinishStopping, object: agent)
        precondition(process.recorder.begun == [1, 2] && process.recorder.ended == [1, 2] && process.latest == nil)
        withExtendedLifetime(source) {}
        print("background activity regressions passed: failed startup acquires none; repeated success/stop balances exactly once")
    }
}
