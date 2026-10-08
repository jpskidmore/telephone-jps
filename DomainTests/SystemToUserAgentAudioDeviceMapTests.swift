//
//  SystemToUserAgentAudioDeviceMapTests.swift
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

@testable import Domain
import DomainTestDoubles
import XCTest

final class SystemToUserAgentAudioDeviceMapTests: XCTestCase {
    private var factory: SystemAudioDeviceTestFactory!

    override func setUp() {
        super.setUp()
        factory = SystemAudioDeviceTestFactory()
    }

    func testMapsSystemToUserAgentDeviceByNameAndIOPort() {
        let systemDevices = factory.all
        let userAgentDevices: [UserAgentAudioDevice] = [
            SimpleUserAgentAudioDevice(device: factory.someInput),
            SimpleUserAgentAudioDevice(device: factory.someOutput)
        ]

        let sut = SystemToUserAgentAudioDeviceMap(systemDevices: systemDevices, userAgentDevices: userAgentDevices)

        XCTAssertTrue(sut.userAgentDevice(for: factory.someInput) == userAgentDevices[0])
        XCTAssertTrue(sut.userAgentDevice(for: factory.someOutput) == userAgentDevices[1])
    }

    func testMapsSystemToUserAgentDeviceByNameAndIOPortWhenTwoDevicesHaveTheSameName() {
        let systemDevices = [factory.firstInput, factory.outputWithNameLikeSomeInput]
        XCTAssertEqual(systemDevices[0].name, systemDevices[1].name)
        XCTAssertTrue(systemDevices[0].hasInputs)
        XCTAssertFalse(systemDevices[0].hasOutputs)
        XCTAssertFalse(systemDevices[1].hasInputs)
        XCTAssertTrue(systemDevices[1].hasOutputs)
        let userAgentDevices: [UserAgentAudioDevice] = [
            SimpleUserAgentAudioDevice(device: systemDevices[1]),
            SimpleUserAgentAudioDevice(device: systemDevices[0])
        ]

        let sut = SystemToUserAgentAudioDeviceMap(systemDevices: systemDevices, userAgentDevices: userAgentDevices)

        XCTAssertTrue(sut.userAgentDevice(for: systemDevices[0]) == userAgentDevices[1])
        XCTAssertTrue(sut.userAgentDevice(for: systemDevices[1]) == userAgentDevices[0])
    }

    func testReturnsNullObjectWhenNoMatchingUserAgentDeviceFound() {
        let sut = SystemToUserAgentAudioDeviceMap(systemDevices: factory.all, userAgentDevices: [])

        let result = sut.userAgentDevice(for: factory.someInput)

        XCTAssertTrue(result.isNil)
    }
}

extension SystemToUserAgentAudioDeviceMapTests {
    func testUIDMappingSurvivesDuplicateNamesAndDifferentEnumerationOrder() {
        let first = SimpleSystemAudioDevice(identifier: 1, uniqueIdentifier: "USB-A", name: "USB Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let second = SimpleSystemAudioDevice(identifier: 2, uniqueIdentifier: "USB-B", name: "USB Headset", inputs: 1, outputs: 1, isBuiltIn: false)
        let native = [
            SimpleUserAgentAudioDevice(identifier: 8, name: "USB Headset", inputs: 1, outputs: 1, uniqueIdentifier: "USB-B"),
            SimpleUserAgentAudioDevice(identifier: 9, name: "Renamed in driver", inputs: 1, outputs: 1, uniqueIdentifier: "USB-A")
        ]
        let map = SystemToUserAgentAudioDeviceMap(systemDevices: [first, second], userAgentDevices: native)
        XCTAssertEqual(map.userAgentDevice(for: first).identifier, 9)
        XCTAssertEqual(map.userAgentDevice(for: second).identifier, 8)
        let ambiguousLegacy = [SimpleUserAgentAudioDevice(identifier: 8, name: "USB Headset", inputs: 1, outputs: 1)]
        let legacyMap = SystemToUserAgentAudioDeviceMap(systemDevices: [first, second], userAgentDevices: ambiguousLegacy)
        XCTAssertTrue(legacyMap.userAgentDevice(for: first).isNil)
        XCTAssertTrue(legacyMap.userAgentDevice(for: second).isNil)
    }
}
