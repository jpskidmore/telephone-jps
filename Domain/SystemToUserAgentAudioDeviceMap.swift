//
//  SystemToUserAgentAudioDeviceMap.swift
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

public final class SystemToUserAgentAudioDeviceMap {
    private var idMap: [SystemAudioDeviceID: UserAgentAudioDeviceID] = [:]
    private let idToUserAgentDevice: [UserAgentAudioDeviceID: UserAgentAudioDevice]
    public init(systemDevices: [SystemAudioDevice], userAgentDevices: [UserAgentAudioDevice]) {
        idToUserAgentDevice = makeIDToDeviceMap(from: userAgentDevices)
        for device in systemDevices {
            let matches = userAgentDevices.filter {
                let identityMatches = !device.uniqueIdentifier.isEmpty && !$0.uniqueIdentifier.isEmpty
                    ? $0.uniqueIdentifier == device.uniqueIdentifier : $0.uniqueIdentifier.isEmpty && $0.name == device.name
                return identityMatches && (!device.hasInputs || $0.hasInputs) && (!device.hasOutputs || $0.hasOutputs)
            }
            // A legacy name is safe only when each side has one compatible device.
            let unambiguousSystemName = systemDevices.filter { $0.name == device.name &&
                (!device.hasInputs || $0.hasInputs) && (!device.hasOutputs || $0.hasOutputs) }.count == 1
            if matches.count == 1 && (!matches[0].uniqueIdentifier.isEmpty || unambiguousSystemName) {
                idMap[device.identifier] = matches[0].identifier
            }
        }
    }

    public func userAgentDevice(for device: SystemAudioDevice) -> UserAgentAudioDevice {
        if let deviceID = idMap[device.identifier], let result = idToUserAgentDevice[deviceID] {
            return result
        } else {
            return NullUserAgentAudioDevice()
        }
    }


}

private func makeIDToDeviceMap(from devices: [UserAgentAudioDevice]) -> [UserAgentAudioDeviceID: UserAgentAudioDevice] {
    var map: [UserAgentAudioDeviceID: UserAgentAudioDevice] = [:]
    devices.forEach({ map[$0.identifier] = $0 })
    return map
}

private typealias SystemAudioDeviceID = Int
private typealias UserAgentAudioDeviceID = Int
