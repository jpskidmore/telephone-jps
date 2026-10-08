//
//  SettingsSoundIOLoadUseCaseTests.swift
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
import Testing
@testable import UseCases
import UseCasesTestDoubles

@MainActor
struct SettingsSoundIOLoadUseCaseTests {
    @Test func callsOutputWithSystemDefaultSoundIOCreatedFromSettingsSoundIOAndAllAudioDevices() throws {
        let factory = SystemAudioDevicesTestFactory(factory: SystemAudioDeviceTestFactory())
        let output = SettingsSoundIOLoadUseCaseOutputSpy()
        let sut = SettingsSoundIOLoadUseCase(factory: factory, settings: SettingsFake(), output: output)

        try sut.execute()

        let invokedSoundIO = try #require(output.invokedSoundIO)
        let devices = try factory.make()
        #expect(
            invokedSoundIO == SystemDefaultingSoundIO(
                SettingsSoundIO(devices: devices, settings: SettingsFake())
            )
        )
        #expect(output.invokedDevices == devices)
    }
}

extension SettingsSoundIOLoadUseCaseTests {
    @Test func savedUIDSurvivesDuplicateNamesRenameAndEnumerationShift() {
        let first = SimpleSystemAudioDevice(identifier: 5, uniqueIdentifier: "USB-A", name: "USB Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let second = SimpleSystemAudioDevice(identifier: 9, uniqueIdentifier: "USB-B", name: "USB Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let settings = SettingsFake()
        let save = SettingsSoundIOSaveUseCase(soundIO: SystemDefaultingSoundIO(
            input: .device(name: second.name, uniqueIdentifier: second.uniqueIdentifier),
            output: .device(name: first.name, uniqueIdentifier: first.uniqueIdentifier),
            ringtoneOutput: .systemDefault), settings: settings)
        save.execute()
        #expect(settings[SettingsKeys.soundInputUID] == "USB-B")
        #expect(settings[SettingsKeys.soundOutputUID] == "USB-A")
        let renamed = SimpleSystemAudioDevice(identifier: 2, uniqueIdentifier: "USB-B", name: "Renamed Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let loaded = SettingsSoundIO(devices: SystemAudioDevices(devices: [renamed, first]), settings: settings)
        #expect(loaded.input.uniqueIdentifier == "USB-B")
        #expect(loaded.input.identifier == 2)
        #expect(loaded.output.uniqueIdentifier == "USB-A")
        #expect(loaded.ringtoneOutput.isNil)
        let removed = SettingsSoundIO(devices: SystemAudioDevices(devices: [first]), settings: settings)
        #expect(removed.input.isNil)
        save.execute()
        let clear = SettingsSoundIOSaveUseCase(soundIO: SystemDefaultingSoundIO(input: .systemDefault, output: .systemDefault, ringtoneOutput: .systemDefault), settings: settings)
        clear.execute()
        #expect(settings[SettingsKeys.soundInputUID] == nil)
        #expect(settings[SettingsKeys.soundOutputUID] == nil)
    }

    @Test func legacyNameMigratesOnlyWhenUnambiguous() {
        let first = SimpleSystemAudioDevice(identifier: 1, uniqueIdentifier: "USB-A", name: "USB Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let second = SimpleSystemAudioDevice(identifier: 2, uniqueIdentifier: "USB-B", name: "USB Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let settings = SettingsFake(); settings[SettingsKeys.soundInput] = "USB Headset"
        let ambiguous = SettingsSoundIO(devices: SystemAudioDevices(devices: [first, second]), settings: settings)
        #expect(ambiguous.input.isNil)
        let legacy = SettingsSoundIO(devices: SystemAudioDevices(devices: [first]), settings: settings)
        #expect(legacy.input.uniqueIdentifier == "USB-A")
        SettingsSoundIOSaveUseCase(soundIO: SystemDefaultingSoundIO(legacy), settings: settings).execute()
        #expect(settings[SettingsKeys.soundInputUID] == "USB-A")
    }
}
