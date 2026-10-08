//
//  CallHistoryCallMakeUseCaseTests.swift
//  Telephone
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

@MainActor
final class CallHistoryCallMakeUseCaseTests: XCTestCase {
    func testGlobalCallbackForwardsProtectedShortAndServiceLiteralsWithoutProviderSIPConversion() async {
        let destinations = ["999", "112", "*21*123#", "12P34"]
        let called = expectation(description: "Every literal reaches current routing"); called.expectedFulfillmentCount = destinations.count * 2
        var invocations: [String] = []
        let sut = CallHistoryCallMakeUseCase(route: { destination, _ in invocations.append(destination); called.fulfill() })
        for destination in destinations {
            for savedDestination in [destination, nil] as [String?] {
                let origin = CallHistoryRecord(uri: URI(user: destination, host: "historical-provider.invalid", displayName: ""),
                                               date: Date(), duration: 2, isIncoming: false, isMissed: false,
                                               canonicalDestination: savedDestination, originAccountUUID: "origin")
                sut.update(record: ContactCallHistoryRecord(origin: origin, contact: MatchedContact(name: "", address: .phone(number: destination, label: ""))))
            }
        }
        await fulfillment(of: [called], timeout: 1)
        XCTAssertEqual(invocations.count, destinations.count * 2)
        XCTAssertEqual(Set(invocations), Set(destinations))
        XCTAssertFalse(invocations.contains { $0.contains("sip:") || $0.contains("historical-provider") })
    }
    func testGlobalCallbackPreservesMatchedNameAndFallsBackToRecordedDisplayName() async {
        let recorded = CallHistoryRecord(uri: URI(user: "123456", host: "", displayName: "Recorded caller"), date: Date(),
                                         duration: 2, isIncoming: true, isMissed: false, canonicalDestination: "+441442123456")
        var names: [String] = []
        let called = expectation(description: "Both names forwarded"); called.expectedFulfillmentCount = 2
        let sut = CallHistoryCallMakeUseCase(routeWithDisplayName: { _, _, name in names.append(name); called.fulfill() })
        sut.update(record: ContactCallHistoryRecord(origin: recorded, contact: MatchedContact(name: "Contacts name", address: .phone(number: "123456", label: "home"))))
        sut.update(record: ContactCallHistoryRecord(origin: recorded, contact: MatchedContact(name: "", address: .phone(number: "123456", label: "home"))))
        await fulfillment(of: [called], timeout: 1)
        XCTAssertEqual(Set(names), ["Contacts name", "Recorded caller"])
    }
    func testGlobalCallbackKeepsCanonicalNumberAndUsesTheCurrentRoutingClosureInsteadOfOriginAccount() async {
        let origin = CallHistoryRecord(uri: URI(user: "123456", host: "old-account", displayName: ""),
                                       date: Date(), duration: 2, isIncoming: false, isMissed: false,
                                       canonicalDestination: "+441442123456", originAccountUUID: "retired-origin", originAccountName: "Old provider")
        let record = ContactCallHistoryRecord(origin: origin, contact: MatchedContact(name: "Contact", address: .phone(number: "123456", label: "home")))
        let called = expectation(description: "Latest routing used")
        let currentRoute = HistoryRouteSelection()
        var invocations: [(String, String, String)] = []
        let sut = CallHistoryCallMakeUseCase(route: { destination, label in
            invocations.append((currentRoute.value, destination, label)); called.fulfill()
        })
        // A dial-plan/account selection changes after the history row was constructed.
        currentRoute.value = "replacement-current-plan"
        sut.update(record: record)
        await fulfillment(of: [called], timeout: 1)
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].0, "replacement-current-plan")
        XCTAssertEqual(invocations[0].1, "+441442123456")
        XCTAssertEqual(invocations[0].2, "home")
    }
    func testMakesCallToURICreatedFromRecordOnUpdate() async {
        let record = ContactCallHistoryRecord(
            origin: CallHistoryRecordTestFactory().makeRecord(number: 1),
            contact: MatchedContact(name: "any", address: .email(address: "any", label: "any"))
        )
        let didCallMakeCall = expectation(description: "Calls makeCall on account")
        let account = AccountSpy(callback: didCallMakeCall.fulfill)
        let sut = CallHistoryCallMakeUseCase(account: account)

        sut.update(record: record)

        await fulfillment(of: [didCallMakeCall], timeout: 1)
        XCTAssertTrue(account.didCallMakeCall)
        XCTAssertEqual(account.invokedURI, URI(record: record))
    }

    func testMakesCallWithLabelFromContactAddressOnUpdate() async {
        let label = "any-label"
        let record = ContactCallHistoryRecord(
            origin: CallHistoryRecordTestFactory().makeRecord(number: 1),
            contact: MatchedContact(name: "any", address: .email(address: "any", label: label))
        )
        let didCallMakeCall = expectation(description: "Calls makeCall on account")
        let account = AccountSpy(callback: didCallMakeCall.fulfill)
        let sut = CallHistoryCallMakeUseCase(account: account)

        sut.update(record: record)

        await fulfillment(of: [didCallMakeCall], timeout: 1)
        XCTAssertTrue(account.didCallMakeCall)
        XCTAssertEqual(account.invokedLabel, label)
    }
}

@MainActor private final class HistoryRouteSelection {
    var value = "first"
}
