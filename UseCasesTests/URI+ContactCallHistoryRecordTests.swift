//
//  URI+ContactCallHistoryRecordTests.swift
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

import XCTest
import UseCases
import UseCasesTestDoubles

final class URI_ContactCallHistoryRecordTests: XCTestCase {
    func testExplicitSIPPortTransportAndIPv6ArePreservedInTheContactConversion() {
        let origin = CallHistoryRecord(uri: URI(user: "desk", address: ServiceAddress(host: "[2001:db8::1]", port: "5071"),
                                                displayName: "", transport: .tls),
                                       date: Date(), duration: 2, isIncoming: false, isMissed: false)
        let record = ContactCallHistoryRecord(origin: origin, contact: MatchedContact(name: "Office", address: .email(address: "desk@example", label: "work")))
        let result = URI(record: record)
        XCTAssertEqual(result.port, "5071")
        XCTAssertEqual(result.host, "2001:db8::1")
        XCTAssertEqual(result.transport, .tls)
        XCTAssertEqual(result.displayName, "Office")
        XCTAssertEqual(origin.callbackDestination, "sip:desk@[2001:db8::1]:5071;transport=tls")
    }
    func testURIIsRecordURIWhenContactNameIsEmpty() {
        let record = ContactCallHistoryRecord(
            origin: CallHistoryRecordTestFactory().makeRecord(number: 1),
            contact: MatchedContact(name: "", address: .email(address: "any", label: "any"))
        )

        let result = URI(record: record)

        XCTAssertEqual(result, record.origin.uri)
    }

    func testURIUserAndHostAreRecordURIUserAndHostButDisplayNameIsContactNameWhenContactNameIsNotEmpty() {
        let record = ContactCallHistoryRecord(
            origin: CallHistoryRecordTestFactory().makeRecord(number: 1),
            contact: MatchedContact(name: "nonempty", address: .email(address: "any", label: "any"))
        )

        let result = URI(record: record)

        XCTAssertEqual(
            result, URI(user: record.origin.uri.user, host: record.origin.uri.host, displayName: record.contact.name)
        )
    }
}
