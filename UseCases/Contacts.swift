//
//  Contacts.swift
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

@ContactsActor
public protocol Contacts: Sendable {
    /// A failure means callers must discard every contact yielded by this attempt.
    func enumerate(_ body: @escaping (Contact) -> Void) -> Result<Void, ContactsLoadFailure>
}

/// These cases carry no contact values or underlying system error descriptions.
public enum ContactsLoadFailure: Error, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    /// A fetch failed while the previous snapshot's access scope is still valid.
    case transient
    /// A fetch failed after access narrowed; the previous snapshot may contain inaccessible contacts.
    case transientWithoutCache
}

public enum ContactsLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    /// A complete successful load, including an empty address book or a genuine no-match.
    case ready
    case unavailable(ContactsLoadFailure)
}
