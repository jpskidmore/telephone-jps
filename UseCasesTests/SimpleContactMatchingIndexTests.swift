//
//  SimpleContactMatchingIndexTests.swift
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

import Testing
@testable import UseCases
import UseCasesTestDoubles

@ContactsActor
struct SimpleContactMatchingIndexTests {
    @Test func findsContactsByPhoneNumberAndEmailAddress() {
        let contact1 = makeContact(number: 1)
        let contact2 = makeContact(number: 2)
        let length = 20
        let sut = SimpleContactMatchingIndex(contacts: SimpleContacts([contact1, contact2]), maxPhoneNumberLength: length)

        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact1.phones[0].number, maxLength: length)) == MatchedContact(contact: contact1, phoneIndex: 0))
        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact1.phones[1].number, maxLength: length)) == MatchedContact(contact: contact1, phoneIndex: 1))
        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact1.emails[0].address)) == MatchedContact(contact: contact1, emailIndex: 0))
        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact1.emails[1].address)) == MatchedContact(contact: contact1, emailIndex: 1))

        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact2.phones[0].number, maxLength: length)) == MatchedContact(contact: contact2, phoneIndex: 0))
        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact2.phones[1].number, maxLength: length)) == MatchedContact(contact: contact2, phoneIndex: 1))
        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact2.emails[0].address)) == MatchedContact(contact: contact2, emailIndex: 0))
        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact2.emails[1].address)) == MatchedContact(contact: contact2, emailIndex: 1))
    }

    @Test func findsContactsByLastDigitsOfThePhoneNumber() {
        let contact1 = makeContact(number: 1)
        let contact2 = makeContact(number: 2)
        let length = 7
        let sut = SimpleContactMatchingIndex(contacts: SimpleContacts([contact1, contact2]), maxPhoneNumberLength: length)

        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact1.phones[0].number, maxLength: length)) == MatchedContact(contact: contact1, phoneIndex:0))
        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact1.phones[1].number, maxLength: length)) == MatchedContact(contact: contact1, phoneIndex:1))
        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact2.phones[0].number, maxLength: length)) == MatchedContact(contact: contact2, phoneIndex:0))
        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact2.phones[1].number, maxLength: length)) == MatchedContact(contact: contact2, phoneIndex:1))
    }

    @Test func findsContactsWithEmailAddressesContainingUppercaseCharacters() {
        let contact1 = Contact(name: "any", phones: [], emails: [Contact.Email(address: "FOO@bar.com", label: "any")])
        let contact2 = Contact(name: "any", phones: [], emails: [Contact.Email(address: "JohnSmith@Company.com", label: "any")])
        let sut = SimpleContactMatchingIndex(contacts: SimpleContacts([contact1, contact2]), maxPhoneNumberLength: 0)

        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact1.emails[0].address)) == MatchedContact(contact: contact1, emailIndex: 0))
        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact2.emails[0].address)) == MatchedContact(contact: contact2, emailIndex: 0))
    }

    @Test func ignoresEmptyAddresses() {
        let contact = Contact(
            name: "any",
            phones: [Contact.Phone(number: "", label: "any")],
            emails: [Contact.Email(address: "", label: "any")]
        )
        let sut = SimpleContactMatchingIndex(contacts: SimpleContacts([contact]), maxPhoneNumberLength: 10)

        #expect(sut.contact(forEmail: NormalizedLowercasedString("")) == nil)
    }

    @Test func buildsCompletionSnapshotFromTheSameSingleSuccessfulEnumeration() {
        let contacts = CompletionCountingContacts([completionContact()])
        let sut = SimpleContactMatchingIndex(contacts: contacts, maxPhoneNumberLength: 20)

        #expect(contacts.enumerationCount == 1)
        #expect(sut.completionSnapshot?.completionStrings(for: "Jane") == [
            "Jane@sip.invalid (Doe Jane)", "Jane Doe <020 123>", "Jane Doe <jane@sip.invalid>", "Jane Doe <desk@sip.invalid>"
        ])
        #expect(sut.contact(forEmail: NormalizedLowercasedString("ordinary@example.invalid"))?.name == "History Name")
        #expect(contacts.enumerationCount == 1)
    }

    @Test(arguments: [ContactsLoadFailure.notDetermined, .denied, .restricted, .transient, .transientWithoutCache])
    func discardsPartialEnumerationWhenLoadingFails(_ failure: ContactsLoadFailure) {
        let contact = makeContact(number: 1)
        let sut = SimpleContactMatchingIndex(
            contacts: SimpleContacts([contact], failure: failure), maxPhoneNumberLength: 20
        )

        #expect(sut.contact(forPhone: ExtractedPhoneNumber(contact.phones[0].number, maxLength: 20)) == nil)
        #expect(sut.contact(forEmail: NormalizedLowercasedString(contact.emails[0].address)) == nil)
        #expect(sut.completionSnapshot == nil)
        guard case .failure(let reportedFailure) = sut.loadResult else {
            Issue.record("A partial Contacts enumeration was reported as successful")
            return
        }
        #expect(reportedFailure == failure)
    }
}

struct ContactCompletionSnapshotTests {
    @Test func preservesOrderedDuplicateFormsRawSIPLabelsAndInputCapitalisation() {
        let contact = completionContact()
        let sut = ContactCompletionSnapshot(contacts: [contact, contact])
        #expect(sut.completionStrings(for: "jane") == [
            "jane@sip.invalid (Doe Jane)", "Jane Doe <020 123>", "Jane Doe <jane@sip.invalid>", "Jane Doe <desk@sip.invalid>",
            "jane@sip.invalid (Doe Jane)", "Jane Doe <020 123>", "Jane Doe <jane@sip.invalid>", "Jane Doe <desk@sip.invalid>"
        ])
        #expect(sut.completionStrings(for: "ordinary").isEmpty)
        #expect(sut.completionStrings(for: "").isEmpty)
        #expect(sut.completionStrings(for: "020") == ["020 123 (Doe Jane)", "020 123 (Doe Jane)"])
    }

    @Test func matchesMultiwordBothOrdersCompanyAndLiteralSpacing() {
        let person = completionContact(given: "Mary Jane", family: "van Dyke")
        let company = Contact(name: "History Company", phones: [.init(number: "123", label: "Test")], emails: [],
                              completionMetadata: .init(identifier: "company", givenName: "Ignored", familyName: "Person",
                                                        organisation: "Acme Training", isCompany: true, displayName: "Acme Training"))
        let sut = ContactCompletionSnapshot(contacts: [person, company])
        #expect(sut.completionStrings(for: "Mary Jane v").first == "Mary Jane van Dyke <020 123>")
        #expect(sut.completionStrings(for: "van Dyke M").first == "van Dyke Mary Jane <020 123>")
        #expect(sut.completionStrings(for: "Mary  Jane").isEmpty)
        #expect(sut.completionStrings(for: "Acme") == ["Acme Training <123>"])
        #expect(sut.completionStrings(for: "Ignored").isEmpty)
    }

    @Test func unnamedTokensSearchPhonesOnlyAndNamedTokensCanMatchAnyEmailLabel() {
        let sut = ContactCompletionSnapshot(contacts: [completionContact()])
        #expect(sut.firstContact(user: "020 123", sipAddress: "020 123", displayName: "")?.completionMetadata?.identifier == "person")
        #expect(sut.firstContact(user: "jane", sipAddress: "jane@sip.invalid", displayName: "") == nil)
        #expect(sut.firstContact(user: "ordinary", sipAddress: "ORDINARY@example.invalid", displayName: "Doe Jane")?.completionMetadata?.identifier == "person")
        #expect(sut.firstContact(user: "jane", sipAddress: "JANE@sip.invalid", displayName: "Jane Doe")?.completionMetadata?.identifier == "person")
        #expect(sut.firstContact(user: "jane", sipAddress: "jane@sip.invalid", displayName: "Unrelated") == nil)
    }

    @Test func renderedNamePrefixDoesNotBypassInitialNameOrAddressAdmission() {
        let leading = completionContact(given: " Mary", family: "Smith")
        let sut = ContactCompletionSnapshot(contacts: [leading])
        #expect(sut.completionStrings(for: " Mary S").isEmpty)
        #expect(sut.completionStrings(for: " Mary ").isEmpty)
        #expect(sut.completionStrings(for: " Mary").count == 3)

        // An ordinary email can admit the record even though it is excluded
        // from completion destinations. This preserves the legacy OR search.
        let emailAdmitted = Contact(name: leading.name, phones: leading.phones,
            emails: leading.emails + [.init(address: " Mary Special@example.invalid", label: "Work", rawLabel: "work")],
            completionMetadata: leading.completionMetadata)
        #expect(ContactCompletionSnapshot(contacts: [emailAdmitted]).completionStrings(for: " Mary S") == [
            " Mary Smith <020 123>", " Mary Smith <jane@sip.invalid>", " Mary Smith <desk@sip.invalid>"
        ])
    }

    @Test func initialNameAdmissionPreservesSparseTrailingAndRepeatedSpaceComponents() {
        let sparse = ContactCompletionSnapshot(contacts: [completionContact(given: "", family: "Onlylast")])
        #expect(sparse.completionStrings(for: " Only").first == "Onlylast <020 123>")
        let trailing = ContactCompletionSnapshot(contacts: [completionContact(given: "Mary ", family: "Smith")])
        #expect(trailing.completionStrings(for: "Mary  S").first == "Mary  Smith <020 123>")
        #expect(trailing.completionStrings(for: "Mary S").isEmpty)
        let repeated = ContactCompletionSnapshot(contacts: [completionContact(given: "Mary  Jane", family: "Smith")])
        #expect(repeated.completionStrings(for: "Mary  Jane S").first == "Mary  Jane Smith <020 123>")
    }

    @Test func excludesIncompleteMetadataAndDoesNotInventNamesForEmptyContacts() {
        let legacy = Contact(name: "Unstructured history name", phones: [.init(number: "123", label: "Test")], emails: [])
        let unnamed = completionContact(given: "", family: "")
        let sut = ContactCompletionSnapshot(contacts: [legacy, unnamed])
        #expect(sut.completionStrings(for: "Unstructured").isEmpty)
        #expect(sut.completionStrings(for: "020") == ["020 123"])
        #expect(sut.firstContact(user: "123", sipAddress: "123", displayName: "") == nil)
    }
}

private func completionContact(given: String = "Jane", family: String = "Doe") -> Contact {
    Contact(name: "History Name", phones: [.init(number: "020 123", label: "Home", rawLabel: "_$!<Home>!$_")],
            emails: [.init(address: "jane@sip.invalid", label: "SIP", rawLabel: "sip"),
                     .init(address: "desk@sip.invalid", label: "SIP", rawLabel: "SIP"),
                     .init(address: "ordinary@example.invalid", label: "Work", rawLabel: "_$!<Work>!$_")],
            completionMetadata: .init(identifier: "person", givenName: given, familyName: family,
                                      organisation: "Example", isCompany: false,
                                      displayName: [family, given].filter { !$0.isEmpty }.joined(separator: " ")))
}

@ContactsActor
private final class CompletionCountingContacts: Contacts {
    let values: [Contact]
    private(set) var enumerationCount = 0
    init(_ values: [Contact]) { self.values = values }
    func enumerate(_ body: @escaping (Contact) -> Void) -> Result<Void, ContactsLoadFailure> {
        enumerationCount += 1
        values.forEach(body)
        return .success(())
    }
}

private func makeContact(number: Int) -> Contact {
    return Contact(name: "name-\(number)", phones: makePhones(number: number), emails: makeEmails(number: number))
}

private func makePhones(number: Int) -> [Contact.Phone] {
    return [
        Contact.Phone(number: "1234567891\(number)", label: "label-\(number)"),
        Contact.Phone(number: "9876543212\(number)", label: "label-\(number)")
    ]
}

private func makeEmails(number: Int) -> [Contact.Email] {
    return [
        Contact.Email(address: "foo\(number)@host", label: "label-\(number)"),
        Contact.Email(address: "bar\(number)@host", label: "label-\(number)")
    ]
}
