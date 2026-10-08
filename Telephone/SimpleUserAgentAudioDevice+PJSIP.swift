//
//  UserAgentAudioDevice+PJSIP.swift
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
import UseCases

extension SimpleUserAgentAudioDevice {
    init(device: pjmedia_aud_dev_info, identifier: Int) throws {
        var uidBytes = [CChar](repeating: 0, count: 1024)
        let status = jps_coreaudio_device_uid(Int32(identifier), &uidBytes, UInt32(uidBytes.count))
        guard status == 0 else { throw UserAgentError.audioDeviceEnumerationError }
        let uid = String(cString: uidBytes)
        guard !uid.isEmpty else { throw UserAgentError.audioDeviceEnumerationError }
        self.init(
            identifier: identifier,
            name: nameOf(device),
            inputs: Int(device.input_count),
            outputs: Int(device.output_count),
            uniqueIdentifier: uid
        )
    }
}

private func nameOf(_ device: pjmedia_aud_dev_info) -> String {
    if let name = String(utf8String: [CChar](tuple: device.name)), !name.isEmpty {
        return name
    } else {
        return NSLocalizedString("Unknown device", comment: "Audio device name is unknown.")
    }
}
