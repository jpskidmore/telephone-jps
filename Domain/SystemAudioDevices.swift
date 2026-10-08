//
//  SystemAudioDevices.swift
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

public struct SystemAudioDevices {
    public let all: [SystemAudioDevice]
    public let input: [SystemAudioDevice]
    public let output: [SystemAudioDevice]

    private let deviceNameToInputDevice: [String: SystemAudioDevice]
    private let deviceNameToOutputDevice: [String: SystemAudioDevice]

    public init(devices: [SystemAudioDevice]) {
        self.all = devices
        input = devices.filter(\.hasInputs)
        output = devices.filter(\.hasOutputs)
        deviceNameToInputDevice = deviceNameToDeviceMap(from: input)
        deviceNameToOutputDevice = deviceNameToDeviceMap(from: output)
    }

    public func inputDevice(uniqueIdentifier: String) -> SystemAudioDevice {
        uniqueDevice(in: input, matching: { $0.uniqueIdentifier == uniqueIdentifier })
    }

    public func outputDevice(uniqueIdentifier: String) -> SystemAudioDevice {
        uniqueDevice(in: output, matching: { $0.uniqueIdentifier == uniqueIdentifier })
    }

    public func inputDevice(named name: String) -> SystemAudioDevice {
        return deviceNameToInputDevice[name] ?? NullSystemAudioDevice()
    }

    public func outputDevice(named name: String) -> SystemAudioDevice {
        return deviceNameToOutputDevice[name] ?? NullSystemAudioDevice()
    }
}

private func deviceNameToDeviceMap(from devices: [SystemAudioDevice]) -> [String: SystemAudioDevice] {
    let groups = Dictionary(grouping: devices, by: \.name)
    return groups.compactMapValues { $0.count == 1 ? $0[0] : nil }
}

private func uniqueDevice(in devices: [SystemAudioDevice], matching predicate: (SystemAudioDevice) -> Bool) -> SystemAudioDevice {
    let matches = devices.filter(predicate)
    return matches.count == 1 ? matches[0] : NullSystemAudioDevice()
}
