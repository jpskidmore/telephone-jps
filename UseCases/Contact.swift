//
//  Contact.swift
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

public struct Contact: Sendable {
    public let name: String
    public let phones: [Phone]
    public let emails: [Email]
    public let completionMetadata: CompletionMetadata?

    public init(name: String, phones: [Phone], emails: [Email], completionMetadata: CompletionMetadata? = nil) {
        self.name = name
        self.phones = phones
        self.emails = emails
        self.completionMetadata = completionMetadata
    }

    public struct CompletionMetadata: Sendable {
        public let identifier: String
        public let givenName: String
        public let familyName: String
        public let organisation: String
        public let isCompany: Bool
        /// Given/family-only display name, independent of the history formatter.
        public let displayName: String

        public init(identifier: String, givenName: String, familyName: String, organisation: String,
                    isCompany: Bool, displayName: String) {
            self.identifier = identifier
            self.givenName = givenName
            self.familyName = familyName
            self.organisation = organisation
            self.isCompany = isCompany
            self.displayName = displayName
        }
    }

    public struct Phone: Sendable {
        public let number: String
        public let label: String
        public let rawLabel: String?

        public init(number: String, label: String, rawLabel: String? = nil) {
            self.number = number
            self.label = label
            self.rawLabel = rawLabel
        }
    }

    public struct Email: Sendable {
        public let address: String
        public let label: String
        public let rawLabel: String?

        public init(address: String, label: String, rawLabel: String? = nil) {
            self.address = address
            self.label = label
            self.rawLabel = rawLabel
        }
    }
}
