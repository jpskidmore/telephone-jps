//
//  SimplePropertyListStorageURLTests.swift
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
@testable import Telephone
import XCTest
import Domain
import UseCases
import UseCasesTestDoubles

final class SimplePropertyListStorageURLTests: XCTestCase {
    func testUsesNameAsFileNameAndPlistAsExtension() {
        let name = "any-name"

        let sut = SimplePropertyListStorageURL(directory: URL(fileURLWithPath: NSTemporaryDirectory()), name: name)

        XCTAssertEqual(sut.url.lastPathComponent, "\(name).plist")
    }
    func testMalformedExistingHistoryThrowsAndMissingFileIsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic.plist")
        let storage = Telephone.SimplePropertyListStorage(url: url, manager: .default)
        XCTAssertTrue(try storage.load().isEmpty)
        try PropertyListSerialization.data(fromPropertyList: ["wrong": "shape"], format: .binary, options: 0).write(to: url)
        let bytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try PropertyListSerialization.data(fromPropertyList: [["user": "partial"]], format: .binary, options: 0).write(to: url)
        XCTAssertThrowsError(try storage.load())
    }

}

// The production event adapters, queued mapper and failure gate run here with
// synthetic factories and a controllable worker. No PJSUA or hardware is started.
@MainActor
final class HotplugRecoveryRegressionTests: XCTestCase {
    func testBackgroundHotplugOrdersRefreshBeforeSelectionAndFactoryFailureStaysLatchedUntilRetry() async {
        for stage in [HotplugFixture.Failure.devices, .defaults, .enumeration] {
            let fixture = HotplugFixture()
            fixture.failure = stage
            let agent = HotplugWorker()
            let selection = makeSelection(fixture, agent)
            let events = UserAgentEventsUserAgentSoundIOSelectionUseCase(useCase: selection, calls: CallsStub(haveActive: true))
            let adapted = AudioDevicesEventsUserAgentSoundIOSelectionUseCase(origin: events)
            let admitted = expectation(description: "selection admitted after refresh")
            agent.onAdmission = { admitted.fulfill() }
            let source = Telephone.MainQueueAudioDeviceEvents(origin: SystemAudioDevicesChangeEventTargets(targets: [
                UserAgentAudioDeviceUpdateUseCase(agent: agent), adapted
            ]))

            DispatchQueue.global().async { source.systemAudioDevicesDidUpdate() }
            await fulfillment(of: [admitted], timeout: 2)
            XCTAssertEqual(agent.admissions, ["refresh", "selection"])
            XCTAssertTrue(agent.admissionsWereOnMain)
            await agent.drain()
            XCTAssertEqual(agent.executions, ["refresh", "selection"])
            XCTAssertTrue(fixture.queriesWereOffMain)
            XCTAssertEqual(agent.backend.nullCalls, 2) // refresh, then failure fallback
            XCTAssertTrue(agent.gate.hasFailed)
            XCTAssertEqual(agent.failureReports, 1)
            XCTAssertEqual(agent.routeRestores, 0)

            // Another implicit hotplug must retain the original failure. Even
            // repaired enumeration cannot reopen a driver while the gate is latched.
            agent.onAdmission = nil
            fixture.failure = .none
            source.systemAudioDevicesDidUpdate()
            await nextMainDelivery()
            await agent.drain()
            XCTAssertTrue(agent.gate.hasFailed)
            XCTAssertEqual(agent.backend.selectCalls, 0)
            XCTAssertEqual(agent.backend.nullCalls, 2)
            XCTAssertEqual(agent.routeRestores, 0)

            // The explicit user retry resets only the gate, then a fresh queued
            // selection maps the synthetic physical UID and restores the route.
            await agent.resetForExplicitRetry()
            try? selection.execute()
            await agent.drain()
            XCTAssertFalse(agent.gate.hasFailed)
            XCTAssertEqual(agent.backend.selectCalls, 1)
            XCTAssertEqual(agent.backend.lastInput, 7)
            XCTAssertEqual(agent.backend.lastOutput, 7)
            XCTAssertEqual(agent.routeRestores, 1)
        }
    }

    func testNativeSelectionFailureDoesNotRetryOnDefaultDeviceChange() async {
        let fixture = HotplugFixture()
        let agent = HotplugWorker()
        agent.backend.selectionStatus = 420003
        let selection = makeSelection(fixture, agent)
        let events = UserAgentEventsUserAgentSoundIOSelectionUseCase(useCase: selection, calls: CallsStub(haveActive: true))
        let source = Telephone.MainQueueDefaultSoundEvents(origin: AudioDevicesEventsUserAgentSoundIOSelectionUseCase(origin: events))
        let admitted = expectation(description: "default device selection on main")
        agent.onAdmission = { admitted.fulfill() }
        DispatchQueue.global().async { source.defaultSystemSoundIODidUpdate() }
        await fulfillment(of: [admitted], timeout: 2)
        await agent.drain()
        XCTAssertTrue(agent.gate.hasFailed)
        XCTAssertEqual(agent.backend.selectCalls, 1)
        XCTAssertEqual(agent.backend.nullCalls, 1)
        agent.onAdmission = nil
        agent.backend.selectionStatus = 0
        source.defaultSystemSoundIODidUpdate()
        await nextMainDelivery()
        await agent.drain()
        XCTAssertTrue(agent.gate.hasFailed)
        XCTAssertEqual(agent.backend.selectCalls, 1)
        XCTAssertEqual(agent.routeRestores, 0)
        await agent.resetForExplicitRetry()
        try? selection.execute()
        await agent.drain()
        XCTAssertFalse(agent.gate.hasFailed)
        XCTAssertEqual(agent.backend.selectCalls, 2)
        XCTAssertEqual(agent.routeRestores, 1)
    }

    func testSupersededMappingFailureCannotLatchNewLifecycle() async {
        let fixture = HotplugFixture()
        fixture.failure = .devices
        let agent = HotplugWorker()
        let selection = makeSelection(fixture, agent)
        try? selection.execute()
        await nextMainDelivery()
        agent.supersedeSelection()
        await agent.drain()
        XCTAssertFalse(agent.gate.hasFailed)
        XCTAssertEqual(agent.failureReports, 0)
        XCTAssertEqual(agent.backend.selectCalls, 0)
        fixture.failure = .none
        try? selection.execute()
        await agent.drain()
        XCTAssertEqual(agent.routeRestores, 1)
    }

    private func makeSelection(_ fixture: HotplugFixture, _ agent: HotplugWorker) -> Telephone.QueuedSoundIOSelectionUseCase {
        Telephone.QueuedSoundIOSelectionUseCase(devicesFactory: fixture, defaultIOFactory: fixture,
            settings: SettingsFake(), agent: agent, userAgentDevices: { try fixture.nativeDevices() })
    }

    private func nextMainDelivery() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
}

private final class HotplugFixture: SystemAudioDevicesFactory, SystemSoundIOFactory {
    enum Failure { case none, devices, defaults, enumeration }
    struct MappingFailure: Error {}
    var failure = Failure.none
    var queriesWereOffMain = true
    let device = SimpleSystemAudioDevice(identifier: 101, uniqueIdentifier: "synthetic:physical-device",
        name: "Synthetic device", inputs: 1, outputs: 2, isBuiltIn: false)
    func make() throws -> SystemAudioDevices {
        queriesWereOffMain = queriesWereOffMain && !Thread.isMainThread
        if failure == .devices { throw MappingFailure() }
        return SystemAudioDevices(devices: [device])
    }
    func make() throws -> SystemSoundIO {
        queriesWereOffMain = queriesWereOffMain && !Thread.isMainThread
        if failure == .defaults { throw MappingFailure() }
        return SimpleSystemSoundIO(input: device, output: device)
    }
    func nativeDevices() throws -> [Domain.UserAgentAudioDevice] {
        queriesWereOffMain = queriesWereOffMain && !Thread.isMainThread
        if failure == .enumeration { throw MappingFailure() }
        return [SimpleUserAgentAudioDevice(identifier: 7, name: device.name, inputs: 1,
            outputs: 2, uniqueIdentifier: device.uniqueIdentifier)]
    }
}

private final class HotplugBackend: NSObject, AKAudioDeviceBackend {
    var nullCalls = 0
    var selectCalls = 0
    var selectionStatus: Int32 = 0
    var lastInput: Int32 = -1
    var lastOutput: Int32 = -1
    func selectInput(_ input: Int32, output: Int32) -> Int32 {
        selectCalls += 1; lastInput = input; lastOutput = output
        return selectionStatus
    }
    func useNullSoundDevice() -> Int32 { nullCalls += 1; return 0 }
    func connectSource(_ source: Int32, destination: Int32) -> Int32 { 0 }
}

// The test transfers one complete batch, awaits its finish, then touches its
// counters/configuration again. Only revision is concurrent and is lock protected.
private struct HotplugWorkerBatch: @unchecked Sendable {
    let operations: [() -> Void]
    func run() { operations.forEach { $0() } }
}

private final class HotplugWorker: Telephone.SoundIOSelectionAgent, UseCases.UserAgent, @unchecked Sendable {
    let isStarted = true
    var maxCalls = 4
    let backend = HotplugBackend()
    lazy var gate = AKAudioDeviceController(backend: backend, logger: { _ in })
    private let lock = NSLock()
    private var revision: UInt = 0
    private var work: [() -> Void] = []
    var admissions: [String] = []
    var executions: [String] = []
    var admissionsWereOnMain = true
    var failureReports = 0
    var routeRestores = 0
    var onAdmission: (() -> Void)?
    func start() {}
    func audioDevices() throws -> [Domain.UserAgentAudioDevice] { [] }
    func selectSoundIODeviceIDs(input: Int, output: Int) throws {}
    func updateAudioDevices() {
        admissionsWereOnMain = admissionsWereOnMain && Thread.isMainThread
        admissions.append("refresh")
        work.append { self.executions.append("refresh"); _ = self.gate.useNullSoundDevice() }
    }
    func performAudioSelection(_ operation: @escaping (UInt) -> Int32) -> Bool {
        admissionsWereOnMain = admissionsWereOnMain && Thread.isMainThread
        admissions.append("selection")
        lock.lock(); revision += 1; let admitted = revision; lock.unlock()
        work.append { self.executions.append("selection"); _ = operation(admitted) }
        onAdmission?()
        return true
    }
    func isAudioSelectionCurrent(_ revision: UInt) -> Bool {
        lock.lock(); defer { lock.unlock() }; return self.revision == revision
    }
    func supersedeSelection() { lock.lock(); revision += 1; lock.unlock() }
    func setSoundInputDevice(_ input: Int, soundOutputDevice output: Int) -> Bool {
        let success = gate.selectInput(Int32(input), output: Int32(output)) == 0
        if success { routeRestores += 1 }
        return success
    }
    func reportAudioSelectionFailure() {
        failureReports += 1
        gate.reportDeviceFailure(70001, operation: "retry-selection")
    }
    @MainActor func drain() async {
        // Let the nonisolated facade admit any main delivery before taking work.
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let pending = HotplugWorkerBatch(operations: work); work.removeAll()
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { pending.run(); continuation.resume() }
        }
    }
    @MainActor func resetForExplicitRetry() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { self.gate.resetFailure(); continuation.resume() }
        }
    }
}
