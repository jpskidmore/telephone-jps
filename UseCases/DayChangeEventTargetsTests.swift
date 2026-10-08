//
//  DayChangeEventTargetsTests.swift
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

@testable import UseCases
import UseCasesTestDoubles
import XCTest

final class DayChangeEventTargetsTests: XCTestCase {
    func testCallsDayDidChangeOnAllTargets() {
        let first = DayChangeEventTargetSpy()
        let second = DayChangeEventTargetSpy()
        let sut = DayChangeEventTargets()
        sut.add(first)
        sut.add(second)

        sut.dayDidChange()

        XCTAssertTrue(first.didCallDayDidChange)
        XCTAssertTrue(second.didCallDayDidChange)
    }
    func testPrunesExpiredSubscribersAndKeepsLiveSubscribers() {
        let sut = DayChangeEventTargets()
        for _ in 0..<100 { sut.add(WeakDayChangeEventTarget(origin: DayChangeEventTargetSpy())) }
        let live = DayChangeEventTargetSpy()
        sut.add(WeakDayChangeEventTarget(origin: live))
        XCTAssertEqual(sut.count, 1)
        sut.dayDidChange()
        XCTAssertTrue(live.didCallDayDidChange)
        XCTAssertEqual(sut.count, 1)
    }

}
