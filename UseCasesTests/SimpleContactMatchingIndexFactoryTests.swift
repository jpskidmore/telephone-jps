//
//  SimpleContactMatchingIndexFactoryTests.swift
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
import XCTest
import UseCasesTestDoubles

@ContactsActor
final class SimpleContactMatchingIndexFactoryTests: XCTestCase {
    func testGetsSignificantPhoneNumberLengthFromSettingsOnMake() async {
        let settings = ContactMatchingSettingsSpy()
        let sut = SimpleContactMatchingIndexFactory(contacts: SimpleContacts([]), settings: settings)

        _ = await sut.make()

        XCTAssertTrue(settings.didCallSignificantPhoneNumberLength)
    }

    func testSuccessfulEmptyAddressBookProducesSuccessfulIndex() async {
        let sut = SimpleContactMatchingIndexFactory(
            contacts: SimpleContacts([]), settings: ContactMatchingSettingsSpy()
        )

        guard case .success(let index) = await sut.make() else {
            XCTFail("An empty but successfully loaded address book must remain distinguishable from failure")
            return
        }
        let result = await index.contact(forEmail: NormalizedLowercasedString("nobody@example.invalid"))
        XCTAssertNil(result)
    }

    func testReturnsTypedFailureRatherThanPublishingPartialIndex() async {
        for expectedFailure in [ContactsLoadFailure.notDetermined, .denied, .restricted, .transient, .transientWithoutCache] {
            let contacts = SimpleContacts(
                [Contact(name: "Synthetic", phones: [], emails: [])], failure: expectedFailure
            )
            let sut = SimpleContactMatchingIndexFactory(contacts: contacts, settings: ContactMatchingSettingsSpy())

            guard case .failure(let failure) = await sut.make() else {
                XCTFail("A failed fetch must not publish a successful empty or partial index")
                return
            }
            XCTAssertEqual(failure, expectedFailure)
        }
    }
}
