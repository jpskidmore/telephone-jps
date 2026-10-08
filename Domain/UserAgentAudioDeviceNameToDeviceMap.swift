//
//  UserAgentAudioDeviceNameToDeviceMap.swift
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

final class UserAgentAudioDeviceNameToDeviceMap {
    private var inputMap: [String: UserAgentAudioDevice] = [:]
    private var devicesForInputName: [String: Int] = [:]
    private var devicesForOutputName: [String: Int] = [:]
    private var outputMap: [String: UserAgentAudioDevice] = [:]

    init(devices: [UserAgentAudioDevice]) {
        devices.forEach(updateInputDeviceMap)
        devices.forEach(updateOutputDeviceMap)
    }

    func inputDevice(named name: String) -> UserAgentAudioDevice {
        return inputMap[name] ?? NullUserAgentAudioDevice()
    }

    func outputDevice(named name: String) -> UserAgentAudioDevice {
        return outputMap[name] ?? NullUserAgentAudioDevice()
    }

    private func updateInputDeviceMap(with device: UserAgentAudioDevice) {
        if device.hasInputs {
            let matches = devicesForInputName[device.name, default: 0] + 1
            devicesForInputName[device.name] = matches
            inputMap[device.name] = matches == 1 ? device : NullUserAgentAudioDevice()
        }
    }

    private func updateOutputDeviceMap(with device: UserAgentAudioDevice) {
        if device.hasOutputs {
            let matches = devicesForOutputName[device.name, default: 0] + 1
            devicesForOutputName[device.name] = matches
            outputMap[device.name] = matches == 1 ? device : NullUserAgentAudioDevice()
        }
    }
}
