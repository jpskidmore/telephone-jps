// Isolated regression checks for actual production Foundation adapters.
// No app host, audio hardware, SIP, Contacts, Keychain, or registry queries.
import Foundation
import UseCases

private final class PlaybackCounts {
    var plays = 0
    var stops = 0
}

private final class CountingSound: Sound {
    private let counts: PlaybackCounts

    init(counts: PlaybackCounts) {
        self.counts = counts
    }

    func play() { counts.plays += 1 }
    func stop() { counts.stops += 1 }
}

private final class TrackingTimerFactory: TimerFactory {
    private let origin = FoundationToUseCasesTimerAdapterFactory()
    private(set) weak var adapter: FoundationToUseCasesTimerAdapter?
    private(set) var creationCount = 0

    func makeRepeatingTimer(interval: Double, action: @escaping () -> Void) -> UseCases.Timer {
        creationCount += 1
        let timer = origin.makeRepeatingTimer(interval: interval, action: action)
        adapter = timer as? FoundationToUseCasesTimerAdapter
        return timer
    }
}

@main
private struct FoundationRegressionHarness {
    @MainActor private static var checks = 0

    @MainActor static func main() {
        testRingtoneOwnerRelease()
        testStoppedRingtoneRelease()
        testUnstartedRingtoneRelease()
        testReminderDefaults()
        testOptionalRegistryProperty()
        print("Foundation regression harness passed \(checks) checks")
    }

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            fatalError("Regression check failed: \(message)")
        }
    }

    @MainActor private static func runLoop(until deadline: Date) {
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    @MainActor private static func testRingtoneOwnerRelease() {
        let counts = PlaybackCounts()
        let factory = TrackingTimerFactory()
        var sound: CountingSound? = CountingSound(counts: counts)
        weak var releasedSound = sound
        var ringtone: RepeatingSound? = RepeatingSound(sound: sound!, interval: 0.01, factory: factory)
        weak var releasedRingtone = ringtone

        ringtone!.startPlaying()
        expect(counts.plays == 1, "ringtone starts immediately")
        expect(factory.creationCount == 1, "ringtone creates one repeating timer")
        let deadline = Date().addingTimeInterval(1)
        while counts.plays < 2 && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: deadline)
        }
        expect(counts.plays >= 2, "actual scheduled Foundation timer repeats playback")

        sound = nil
        ringtone = nil
        expect(releasedRingtone == nil, "ringtone owner releases")
        expect(counts.stops == 1, "active sound stops on owner release")
        expect(factory.adapter == nil, "invalidation breaks scheduled timer and target retention")
        expect(releasedSound == nil, "timer action releases the sound")
        let previousPlays = counts.plays
        runLoop(until: Date().addingTimeInterval(0.05))
        expect(counts.plays == previousPlays, "released ringtone cannot fire again")
    }

    @MainActor private static func testStoppedRingtoneRelease() {
        let counts = PlaybackCounts()
        let factory = TrackingTimerFactory()
        var ringtone: RepeatingSound? = RepeatingSound(sound: CountingSound(counts: counts), interval: 60, factory: factory)
        ringtone!.startPlaying()
        ringtone!.startPlaying()
        expect(factory.creationCount == 1, "consecutive starts reuse the repeating timer")
        ringtone!.stopPlaying()
        expect(factory.adapter == nil, "explicit stop releases the timer target")
        expect(counts.stops == 1, "explicit stop stops playback")
        ringtone = nil
        expect(counts.stops == 1, "teardown after explicit stop does not stop twice")
    }

    @MainActor private static func testUnstartedRingtoneRelease() {
        let counts = PlaybackCounts()
        let factory = TrackingTimerFactory()
        var ringtone: RepeatingSound? = RepeatingSound(sound: CountingSound(counts: counts), interval: 60, factory: factory)
        weak var releasedRingtone = ringtone
        ringtone = nil
        expect(releasedRingtone == nil, "unstarted ringtone releases")
        expect(factory.creationCount == 0, "unstarted ringtone has no timer")
        expect(counts.stops == 0, "unstarted sound does not receive a redundant stop")
    }

    @MainActor private static func testReminderDefaults() {
        let suite = "uk.jpsit.telephone.foundation-regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UserDefaultsPurchaseReminderSettings(defaults: defaults)
        expect(settings.date == .distantPast, "missing reminder date uses the established default")
        expect(settings.version == "", "missing reminder version uses the established default")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        settings.date = date
        settings.version = "2.1.3"
        expect(settings.date == date, "valid reminder date round trips")
        expect(settings.version == "2.1.3", "valid reminder version round trips")
        defaults.set("invalid-date", forKey: "PurchaseReminderDate")
        defaults.set(["invalid-version"], forKey: "PurchaseReminderVersion")
        expect(settings.date == .distantPast, "wrong-type stored reminder date does not crash")
        expect(settings.version == "", "wrong-type stored reminder version does not crash")
        settings.date = date
        settings.version = "2.1.3"
        expect(settings.date == date && settings.version == "2.1.3", "valid writes recover invalid settings")
    }

    @MainActor private static func testOptionalRegistryProperty() {
        expect(DeviceGUID.macAddressData(from: nil) == nil, "absent IOKit property does not crash")
        let wrongType = Unmanaged<CFTypeRef>.passRetained(NSString(string: "not-MAC-data"))
        expect(DeviceGUID.macAddressData(from: wrongType) == nil, "wrong-type IOKit property does not crash")
        let bytes = Data([0x02, 0x11, 0x22, 0x33, 0x44, 0x55])
        let property = Unmanaged<CFTypeRef>.passRetained(bytes as NSData)
        expect(DeviceGUID.macAddressData(from: property) == bytes, "valid IOKit MAC data retains its exact bytes")
    }
}
