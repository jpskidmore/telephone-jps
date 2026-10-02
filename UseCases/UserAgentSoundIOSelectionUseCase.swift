//
//  UserAgentSoundIOSelectionUseCase.swift
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

public final class UserAgentSoundIOSelectionUseCase {
    private let devicesFactory: SystemAudioDevicesFactory
    private let soundIOFactory: SoundIOFactory
    private let agent: UserAgent

    public init(devicesFactory: SystemAudioDevicesFactory, soundIOFactory: SoundIOFactory, agent: UserAgent) {
        self.devicesFactory = devicesFactory
        self.soundIOFactory = soundIOFactory
        self.agent = agent
    }
}

extension UserAgentSoundIOSelectionUseCase: ThrowingUseCase {
    public func execute() throws {
        let devices = try devicesFactory.make()
        let deviceMap = SystemToUserAgentAudioDeviceMap(
            systemDevices: devices.all, userAgentDevices: try agent.audioDevices().map(SimpleUserAgentAudioDevice.init)
        )
        let soundIO = try soundIOFactory.make()
        try agent.selectSoundIODeviceIDs(
            input: deviceMap.userAgentDevice(for: soundIO.input).identifier,
            output: deviceMap.userAgentDevice(for: soundIO.output).identifier
        )
    }
}
