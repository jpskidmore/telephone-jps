//
//  SoundPreferencesViewEventTargetTests.swift
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

import Testing
import UseCases
import UseCasesTestDoubles
import Domain
import XCTest
@testable import Telephone

@MainActor
struct SoundPreferencesViewEventTargetTests {
    private let factory = UseCaseFactorySpy()
    private let userAgentSoundIOSelection = UseCaseSpy()
    private let ringtoneOutputUpdate = ThrowingUseCaseSpy()
    private let soundPlayback = SoundPlaybackUseCaseSpy()
    private let sut: SoundPreferencesViewEventTarget

    init() {
        sut = SoundPreferencesViewEventTarget(
            useCaseFactory: factory,
            presenterFactory: PresenterFactory(),
            userAgentSoundIOSelection: userAgentSoundIOSelection,
            ringtoneOutputUpdate: ringtoneOutputUpdate,
            ringtoneSoundPlayback: soundPlayback
        )
    }

    @Test func executesSettingsSoundIOLoadUseCaseOnViewDataReload() {
        let useCase = ThrowingUseCaseSpy()
        factory.stub(withSettingsSoundIOLoad: useCase)

        sut.shouldReloadData(in: SoundPreferencesViewSpy())

        #expect(useCase.didCallExecute)
    }

    @Test func executesSettingsSoundIOLoadUseCaseOnSoundIOReload() {
        let useCase = ThrowingUseCaseSpy()
        factory.stub(withSettingsSoundIOLoad: useCase)

        sut.shouldReloadSoundIO(in: SoundPreferencesViewSpy())

        #expect(useCase.didCallExecute)
    }

    @Test func executesSettingsSoundIOSaveUseCaseWithExpectedArgumentOnSoundIOChange() {
        let useCase = UseCaseSpy()
        factory.stub(withSettingsSoundIOSave: useCase)
        let soundIO = makePresentationSoundIO()

        sut.didChangeSoundIO(soundIO)

        #expect(factory.invokedSoundIO == SystemDefaultingSoundIO(soundIO))
        #expect(useCase.didCallExecute)
    }

    @Test func executesUserAgentSoundIOSelectionUseCaseOnSoundIOChange() {
        factory.stub(withSettingsSoundIOSave: UseCaseSpy())

        sut.didChangeSoundIO(makePresentationSoundIO())

        #expect(userAgentSoundIOSelection.didCallExecute)
    }

    @Test func executesRingtoneOutputUpdateUseCaseOnSoundIOChange() {
        factory.stub(withSettingsSoundIOSave: UseCaseSpy())

        sut.didChangeSoundIO(makePresentationSoundIO())

        #expect(ringtoneOutputUpdate.didCallExecute)
    }

    @Test func executesSettingsRingtoneSoundNameSaveUseCaseWithExpectedArgumentsOnRingtoneNameChange() {
        let useCase = UseCaseSpy()
        factory.stub(withSettingsRingtoneSoundNameSave: useCase)

        sut.didChangeRingtoneName("sound-name")

        #expect(factory.invokedRingtoneSoundName == "sound-name")
        #expect(useCase.didCallExecute)
    }

    @Test func playsRingtoneSoundOnRingtoneNameChange() {
        factory.stub(withSettingsRingtoneSoundNameSave: UseCaseSpy())

        sut.didChangeRingtoneName("any-name")

        #expect(soundPlayback.didCallPlay)
    }

    @Test func stopsPlayingRingtoneSoundOnViewWillDisappear() {
        sut.willDisappear(SoundPreferencesViewSpy())

        #expect(soundPlayback.didCallStop)
    }
}

private func makePresentationSoundIO() -> PresentationSoundIO {
    return PresentationSoundIO(
        input: PresentationAudioDevice(isSystemDefault: false, name: "any-input"),
        output: PresentationAudioDevice(isSystemDefault: false, name: "any-output"),
        ringtoneOutput: PresentationAudioDevice(isSystemDefault: false, name: "other-output")
    )
}

private struct V30FailingSoundLoad: ThrowingUseCase {
    func execute() throws { throw NSError(domain: "Synthetic device query", code: 1) }
}

extension SoundPreferencesViewEventTargetTests {
    @Test func displaysRecoverableQueryFailureToTheActualViewBoundary() {
        factory.stub(withSettingsSoundIOLoad: V30FailingSoundLoad())
        let view = SoundPreferencesViewSpy()
        sut.shouldReloadData(in: view)
        #expect(view.invokedLoadError?.contains("Reopen Sound settings") == true)
        #expect(view.invokedDevices == nil)
    }
}

// Exercise the actual production admission/UID mapping wrapper. The factories
// and SDK worker boundaries are synthetic; no CoreAudio/PJSUA is initialised.
private final class V30QueuedSelectionAgent: Telephone.SoundIOSelectionAgent, @unchecked Sendable {
    let worker = DispatchQueue(label: "v30.synthetic-audio-control")
    private let lock = NSLock()
    private var revision: UInt = 0
    private var pending = false
    private var selected: [(Int, Int)] = []
    private var failures = 0
    var completed: (() -> Void)?
    var isStarted: Bool { true }
    var commandPending: Bool { lock.lock(); defer { lock.unlock() }; return pending }
    var selections: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return selected }
    var failureCount: Int { lock.lock(); defer { lock.unlock() }; return failures }
    func performAudioSelection(_ operation: @escaping (UInt) -> Int32) -> Bool {
        XCTAssertTrue(Thread.isMainThread)
        lock.lock(); revision += 1; let request = revision; pending = true; lock.unlock()
        worker.async {
            _ = operation(request)
            DispatchQueue.main.async {
                self.lock.lock(); if self.revision == request { self.pending = false }; self.lock.unlock()
                self.completed?()
            }
        }
        return true
    }
    func isAudioSelectionCurrent(_ request: UInt) -> Bool {
        lock.lock(); defer { lock.unlock() }; return request == revision
    }
    func setSoundInputDevice(_ input: Int, soundOutputDevice output: Int) -> Bool {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); selected.append((input, output)); lock.unlock(); return true
    }
    func reportAudioSelectionFailure() { lock.lock(); failures += 1; lock.unlock() }
}

private final class V30BlockedDevices: SystemAudioDevicesFactory, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let devices: Domain.SystemAudioDevices
    let firstQuery: XCTestExpectation
    let failFirst: Bool
    private var calls = 0
    init(devices: Domain.SystemAudioDevices, firstQuery: XCTestExpectation, failFirst: Bool) {
        self.devices = devices; self.firstQuery = firstQuery; self.failFirst = failFirst
    }
    func make() throws -> Domain.SystemAudioDevices {
        XCTAssertFalse(Thread.isMainThread)
        calls += 1
        if calls == 1 {
            firstQuery.fulfill()
            if release.wait(timeout: .now() + 3) != .success { throw NSError(domain: "Fixture timeout", code: 1) }
            if failFirst { throw NSError(domain: "Synthetic stale enumeration", code: 1) }
        }
        return devices
    }
}

private struct V30DefaultIO: SystemSoundIOFactory {
    let io: Domain.SystemSoundIO
    func make() throws -> Domain.SystemSoundIO { XCTAssertFalse(Thread.isMainThread); return io }
}

@MainActor
final class V30QueuedAudioSelectionTests: XCTestCase {
    private func device(_ uid: String, id: Int) -> Domain.SimpleSystemAudioDevice {
        Domain.SimpleSystemAudioDevice(identifier: id, uniqueIdentifier: uid, name: "Duplicate headset", inputs: 1, outputs: 1, isBuiltIn: false)
    }

    func testBlockedEnumerationKeepsMainResponsiveAndUsesTheLatestImmutableUIDSnapshot() async throws {
        let first = device("UID-A", id: 101), second = device("UID-B", id: 202)
        let queried = expectation(description: "Real wrapper entered worker query")
        let complete = expectation(description: "Both requests completed"); complete.expectedFulfillmentCount = 2
        let factory = V30BlockedDevices(devices: Domain.SystemAudioDevices(devices: [first, second]), firstQuery: queried, failFirst: true)
        let agent = V30QueuedSelectionAgent(); agent.completed = complete.fulfill
        let settings = SettingsFake(); settings[SettingsKeys.soundInputUID] = "UID-A"; settings[SettingsKeys.soundOutputUID] = "UID-A"
        let sut = Telephone.QueuedSoundIOSelectionUseCase(devicesFactory: factory,
            defaultIOFactory: V30DefaultIO(io: Domain.SimpleSystemSoundIO(input: first, output: first)), settings: settings, agent: agent,
            userAgentDevices: {
                XCTAssertFalse(Thread.isMainThread)
                return [Domain.SimpleUserAgentAudioDevice(identifier: 7, name: "Duplicate headset", inputs: 1, outputs: 1, uniqueIdentifier: "UID-A"),
                        Domain.SimpleUserAgentAudioDevice(identifier: 3, name: "Duplicate headset", inputs: 1, outputs: 1, uniqueIdentifier: "UID-B")]
            })
        try sut.execute(); XCTAssertTrue(agent.commandPending)
        await fulfillment(of: [queried], timeout: 2)
        let uiTick = expectation(description: "Main remains responsive during blocked enumeration")
        DispatchQueue.main.async { uiTick.fulfill() }
        await fulfillment(of: [uiTick], timeout: 1)
        settings[SettingsKeys.soundInputUID] = "UID-B"; settings[SettingsKeys.soundOutputUID] = "UID-B"
        try sut.execute(); XCTAssertTrue(agent.commandPending)
        // Edits made after admission do not change the accepted snapshot.
        settings[SettingsKeys.soundInputUID] = "UID-A"; settings[SettingsKeys.soundOutputUID] = "UID-A"
        factory.release.signal()
        await fulfillment(of: [complete], timeout: 3)
        XCTAssertFalse(agent.commandPending); XCTAssertEqual(agent.failureCount, 0)
        XCTAssertEqual(agent.selections.count, 1)
        XCTAssertEqual(agent.selections.first?.0, 3); XCTAssertEqual(agent.selections.first?.1, 3)
    }

    func testBackgroundEntryHopsToMainBeforeCapturingSettingsAndAdmittingWorker() async throws {
        let first = device("UID-A", id: 101)
        let queried = expectation(description: "Background entry reaches queued enumeration")
        let complete = expectation(description: "Background request completes")
        let factory = V30BlockedDevices(devices: Domain.SystemAudioDevices(devices: [first]), firstQuery: queried, failFirst: false)
        let agent = V30QueuedSelectionAgent(); agent.completed = complete.fulfill
        let settings = SettingsFake(); settings[SettingsKeys.soundInputUID] = "UID-A"
        let sut = Telephone.QueuedSoundIOSelectionUseCase(devicesFactory: factory,
            defaultIOFactory: V30DefaultIO(io: Domain.SimpleSystemSoundIO(input: first, output: first)), settings: settings, agent: agent,
            userAgentDevices: { [Domain.SimpleUserAgentAudioDevice(identifier: 4, name: "Duplicate headset", inputs: 1, outputs: 1, uniqueIdentifier: "UID-A")] })
        let boundary: ThrowingUseCase = sut
        DispatchQueue.global().async { try? boundary.execute() }
        await fulfillment(of: [queried], timeout: 2)
        XCTAssertTrue(agent.commandPending); factory.release.signal()
        await fulfillment(of: [complete], timeout: 3)
        XCTAssertEqual(agent.selections.first?.0, 4); XCTAssertEqual(agent.failureCount, 0)
    }
}
