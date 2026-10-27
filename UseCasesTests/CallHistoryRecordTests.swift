//
//  CallHistoryRecordTests.swift
//  UseCasesTests
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
import XCTest

final class CallHistoryRecordTests: XCTestCase {
    func testRecordingCallKeySurvivesHistoryTransformsWithoutChangingLegacyIdentity() {
        let uri = URI(user: "desk", host: "example.invalid", displayName: "Desk")
        let date = Date(timeIntervalSinceReferenceDate: 10)
        let legacy = CallHistoryRecord(uri: uri, date: date, duration: 2, isIncoming: false, isMissed: false)
        let linked = CallHistoryRecord(uri: uri, date: date, duration: 2, isIncoming: false, isMissed: false,
                                       recordingCallIdentifier: "opaque-call")
        XCTAssertNil(legacy.recordingCallIdentifier)
        XCTAssertEqual(linked.identifier, legacy.identifier)
        XCTAssertEqual(linked.accountRecordIdentifier, legacy.accountRecordIdentifier)
        XCTAssertNotEqual(linked, legacy, "Attachment metadata changes must propagate to readers")
        let qualified = linked.qualified(accountUUID: "account-a", accountName: "Provider")
        XCTAssertEqual(qualified.recordingCallIdentifier, "opaque-call")
        XCTAssertEqual(qualified.accountRecordIdentifier, linked.accountRecordIdentifier)
        XCTAssertEqual(qualified.removingHost().recordingCallIdentifier, "opaque-call")
    }

    func testRecordingCallKeyDoesNotDependOnFinalDurationOrRemoteAddress() {
        let records = [2, 200].map { duration in
            CallHistoryRecord(uri: URI(user: "desk", host: "example.invalid", displayName: ""),
                              date: Date(timeIntervalSinceReferenceDate: 10), duration: duration, isIncoming: false,
                              isMissed: false, recordingCallIdentifier: "same-call")
        }
        XCTAssertNotEqual(records[0].identifier, records[1].identifier)
        XCTAssertEqual(records[0].recordingCallIdentifier, records[1].recordingCallIdentifier)
        let redial = CallHistoryRecord(uri: records[0].uri, date: records[0].date, duration: 2,
                                       isIncoming: false, isMissed: false, recordingCallIdentifier: "different-call")
        XCTAssertNotEqual(redial.recordingCallIdentifier, records[0].recordingCallIdentifier)
    }

    func testEmptyRecordingCallKeyRemainsUnlinked() {
        let record = CallHistoryRecord(uri: URI(user: "desk", host: "", displayName: ""), date: Date(),
                                       duration: 0, isIncoming: false, isMissed: false, recordingCallIdentifier: "")
        XCTAssertNil(record.recordingCallIdentifier)
    }

    func testLegacyDispatchFallbackProtectsLiteralsWhileExplicitSIPMetadataRetainsItsDestination() {
        for literal in ["999", "112", "*21*123#", "12P34", "+441442123456"] {
            let record = CallHistoryRecord(uri: URI(user: literal, host: "historical-provider.invalid", displayName: ""),
                                           date: Date(), duration: 1, isIncoming: false, isMissed: false)
            XCTAssertEqual(record.callbackDestination, literal)
            XCTAssertNil(record.canonicalDestination, "Reading a callback must not populate guessed metadata")
        }
        let alpha = CallHistoryRecord(uri: URI(user: "desk", address: ServiceAddress(host: "example.test", port: "5071"),
                                               displayName: "Caller", transport: .tls),
                                      date: Date(), duration: 1, isIncoming: false, isMissed: false)
        XCTAssertEqual(alpha.callbackDestination, "sip:desk@example.test:5071;transport=tls")
        let explicit = "sip:999@example.test:5071;transport=tls"
        let numericSIP = CallHistoryRecord(uri: URI(user: "999", host: "example.test", displayName: ""),
                                           date: Date(), duration: 1, isIncoming: false, isMissed: false, canonicalDestination: explicit)
        XCTAssertEqual(numericSIP.callbackDestination, explicit)
    }
    func testIdentifierContainsUserHostDateDurationIncomingFlag() {
        let user = "any-user"
        let host = "any-host"
        let date = Date()
        let duration = 10

        let sut = CallHistoryRecord(
            uri: URI(user: user, host: host, displayName: ""),
            date: date,
            duration: duration,
            isIncoming: true,
            isMissed: false
        )

        XCTAssertEqual(
            sut.identifier,
            "\(user)@\(host)|\(date.timeIntervalSinceReferenceDate)|\(duration)|\(sut.isIncoming ? 1 : 0)"
        )
    }
}
