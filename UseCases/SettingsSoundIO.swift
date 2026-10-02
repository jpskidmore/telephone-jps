//
//  SettingsSoundIO.swift
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

@MainActor
struct SettingsSoundIO: SoundIO {
    let input: SystemAudioDevice
    let output: SystemAudioDevice
    let ringtoneOutput: SystemAudioDevice

    init(devices: SystemAudioDevices, settings: KeyValueSettings) {
        input = Self.device(withName: settings.string(forKey: SettingsKeys.soundInput), lookup: devices.inputDevice)
        output = Self.device(withName: settings.string(forKey: SettingsKeys.soundOutput), lookup: devices.outputDevice)
        ringtoneOutput = Self.device(withName: settings.string(forKey: SettingsKeys.ringtoneOutput), lookup: devices.outputDevice)
    }

    private static func device(withName name: String?, lookup: (String) -> SystemAudioDevice) -> SystemAudioDevice {
        if let name = name {
            return lookup(name)
        } else {
            return NullSystemAudioDevice()
        }
    }
}
