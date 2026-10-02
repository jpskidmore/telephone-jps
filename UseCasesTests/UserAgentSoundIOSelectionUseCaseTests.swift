//
//  UserAgentSoundIOSelectionUseCaseTests.swift
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

import Domain
import DomainTestDoubles
@testable import UseCases
import UseCasesTestDoubles
import XCTest

final class UserAgentSoundIOSelectionUseCaseTests: XCTestCase {
    func testSelectsDeviceIdentifiersOfSoundIO() throws {
        let input = SystemAudioDeviceTestFactory().someInput
        let output = SystemAudioDeviceTestFactory().someOutput
        let agent = UserAgentSpy()
        agent.audioDevicesResult = [
            SimpleUserAgentAudioDevice(device: output), SimpleUserAgentAudioDevice(device: input)
        ]
        let sut = UserAgentSoundIOSelectionUseCase(
            devicesFactory: SystemAudioDevicesTestFactory(factory: SystemAudioDeviceTestFactory()),
            soundIOFactory: SoundIOFactoryStub(
                soundIO: SimpleSoundIO(input: input, output: output, ringtoneOutput: NullSystemAudioDevice())
            ),
            agent: agent
        )

        try sut.execute()

        XCTAssertEqual(agent.invokedInputDeviceID, input.identifier)
        XCTAssertEqual(agent.invokedOutputDeviceID, output.identifier)
    }

    func testReadsDependenciesAndSelectsInOrder() throws {
        let environment = SoundIOSelectionEnvironment()
        let sut = environment.makeUseCase()

        try sut.execute()

        XCTAssertEqual(environment.operations, SoundIOSelectionEnvironment.steps)
    }

    func testPropagatesEachDependencyFailureAndDoesNotRunLaterSteps() {
        for (index, step) in SoundIOSelectionEnvironment.steps.enumerated() {
            let environment = SoundIOSelectionEnvironment()
            environment.failingStep = step
            let sut = environment.makeUseCase()

            XCTAssertThrowsError(try sut.execute()) { error in
                XCTAssertEqual(error as? SoundIOSelectionFailure, .expected)
            }

            XCTAssertEqual(environment.operations, Array(SoundIOSelectionEnvironment.steps.prefix(index + 1)))
        }
    }

    func testReloadsDevicesAndSoundIOOnEveryExecution() throws {
        let environment = SoundIOSelectionEnvironment()
        let sut = environment.makeUseCase()
        try sut.execute()

        environment.useAlternativeDevices()
        try sut.execute()

        XCTAssertEqual(environment.operations, SoundIOSelectionEnvironment.steps + SoundIOSelectionEnvironment.steps)
        XCTAssertEqual(environment.selectedInput, 101)
        XCTAssertEqual(environment.selectedOutput, 102)
    }

    func testRetriesWithFreshDependenciesAfterEachFailure() throws {
        for step in SoundIOSelectionEnvironment.steps {
            let environment = SoundIOSelectionEnvironment()
            environment.failingStep = step
            let sut = environment.makeUseCase()
            XCTAssertThrowsError(try sut.execute())

            environment.failingStep = nil
            environment.operations = []
            environment.useAlternativeDevices()
            try sut.execute()

            XCTAssertEqual(environment.operations, SoundIOSelectionEnvironment.steps)
            XCTAssertEqual(environment.selectedInput, 101)
            XCTAssertEqual(environment.selectedOutput, 102)
        }
    }
}

private enum SoundIOSelectionFailure: Error, Equatable {
    case expected
}

private final class SoundIOSelectionEnvironment: UserAgent {
    static let steps = ["systemDevices", "audioDevices", "soundIO", "select"]

    var operations: [String] = []
    var failingStep: String?
    var isStarted = false
    var maxCalls = 0
    private(set) var selectedInput: Int?
    private(set) var selectedOutput: Int?

    private var devices: [SystemAudioDevice]
    private var soundIO: SoundIO
    private var userAgentDevices: [UserAgentAudioDevice]

    init() {
        let factory = SystemAudioDeviceTestFactory()
        devices = factory.all
        soundIO = SimpleSoundIO(input: factory.someInput, output: factory.someOutput, ringtoneOutput: NullSystemAudioDevice())
        userAgentDevices = [
            SimpleUserAgentAudioDevice(device: factory.someInput),
            SimpleUserAgentAudioDevice(device: factory.someOutput)
        ]
    }

    func makeUseCase() -> UserAgentSoundIOSelectionUseCase {
        return UserAgentSoundIOSelectionUseCase(
            devicesFactory: ClosureSystemAudioDevicesFactory {
                try self.record("systemDevices")
                return SystemAudioDevices(devices: self.devices)
            },
            soundIOFactory: ClosureSoundIOFactory {
                try self.record("soundIO")
                return self.soundIO
            },
            agent: self
        )
    }

    func useAlternativeDevices() {
        let factory = SystemAudioDeviceTestFactory()
        devices = [factory.firstInput, factory.firstOutput]
        soundIO = SimpleSoundIO(input: factory.firstInput, output: factory.firstOutput, ringtoneOutput: NullSystemAudioDevice())
        userAgentDevices = [
            SimpleUserAgentAudioDevice(identifier: 101, name: factory.firstInput.name, inputs: 1, outputs: 0),
            SimpleUserAgentAudioDevice(identifier: 102, name: factory.firstOutput.name, inputs: 0, outputs: 1)
        ]
    }

    func start() {}
    func updateAudioDevices() {}

    func audioDevices() throws -> [UserAgentAudioDevice] {
        try record("audioDevices")
        return userAgentDevices
    }

    func selectSoundIODeviceIDs(input: Int, output: Int) throws {
        try record("select")
        selectedInput = input
        selectedOutput = output
    }

    private func record(_ step: String) throws {
        operations.append(step)
        if failingStep == step {
            throw SoundIOSelectionFailure.expected
        }
    }
}

private struct ClosureSystemAudioDevicesFactory: SystemAudioDevicesFactory {
    let makeBody: () throws -> SystemAudioDevices

    func make() throws -> SystemAudioDevices {
        return try makeBody()
    }
}

private struct ClosureSoundIOFactory: SoundIOFactory {
    let makeBody: () throws -> SoundIO

    func make() throws -> SoundIO {
        return try makeBody()
    }
}
