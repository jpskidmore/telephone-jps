//
//  RepeatingSoundFactoryTests.swift
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

import UseCases
import UseCasesTestDoubles
import XCTest

final class RepeatingSoundFactoryTests: XCTestCase {
    private var factory: SoundFactorySpy!
    private var sut: RepeatingSoundFactory!

    override func setUp() {
        super.setUp()
        factory = SoundFactorySpy()
        let timerFactory = TimerFactorySpy()
        timerFactory.stub(with: TimerSpy())
        sut = RepeatingSoundFactory(soundFactory: factory, timerFactory: timerFactory)
    }

    func testCallsCreateSound() {
        try! _ = sut.makeRingtone(interval: 0)

        XCTAssertTrue(factory.didCallCreateSound)
    }

    func testCreatesRingtoneWithSpecifiedInterval() {
        let interval: Double = 2

        let result = try! sut.makeRingtone(interval: interval)

        XCTAssertEqual(result.interval, interval)
    }

    func testRingtonePlaysAndStopsTheCreatedSound() throws {
        let ringtone = try sut.makeRingtone(interval: 2)
        let sound = try XCTUnwrap(factory.lastCreatedSound)

        ringtone.startPlaying()
        XCTAssertTrue(sound.didCallPlay)
        ringtone.stopPlaying()
        XCTAssertTrue(sound.didCallStop)
    }

    func testPropagatesSoundCreationFailure() {
        let sut = RepeatingSoundFactory(soundFactory: FailingSoundFactory(), timerFactory: TimerFactorySpy())

        XCTAssertThrowsError(try sut.makeRingtone(interval: 2)) { error in
            XCTAssertEqual(error as? SoundCreationFailure, .expected)
        }
    }
}

private enum SoundCreationFailure: Error, Equatable {
    case expected
}

private struct FailingSoundFactory: SoundFactory {
    func makeSound(target: SoundEventTarget) throws -> Sound {
        throw SoundCreationFailure.expected
    }
}
