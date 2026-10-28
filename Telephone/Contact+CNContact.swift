//
//  Contact+CNContact.swift
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

import Contacts
import UseCases

extension Contact {
    init(_ contact: CNContact) {
        let isCompany = contact.contactType == .organization
        let components = CNContactFormatter.nameOrder(for: contact) == .familyNameFirst
            ? [contact.familyName, contact.givenName] : [contact.givenName, contact.familyName]
        let completionDisplayName = isCompany ? contact.organizationName
            : components.filter { !$0.isEmpty }.joined(separator: " ")
        self.init(
            name: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
            phones: contact.phoneNumbers.map(Contact.Phone.init),
            emails: contact.emailAddresses.map(Contact.Email.init),
            completionMetadata: .init(identifier: contact.identifier, givenName: contact.givenName,
                                      familyName: contact.familyName, organisation: contact.organizationName,
                                      isCompany: isCompany, displayName: completionDisplayName)
        )
    }
}

extension Contact.Phone {
    init(_ phone: CNLabeledValue<CNPhoneNumber>) {
        self.init(
            number: phone.value.stringValue,
            label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? ""),
            rawLabel: phone.label
        )
    }
}

extension Contact.Email {
    init(_ email: CNLabeledValue<NSString>) {
        self.init(
            address: email.value as String, label: CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? ""),
            rawLabel: email.label
        )
    }
}
