//
//  CNContactStoreToContactsAdapter.swift
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

@preconcurrency import Contacts
import UseCases

@ContactsActor
final class CNContactStoreToContactsAdapter: UseCases.Contacts {
    private let authorization: @Sendable () -> CNAuthorizationStatus
    private let fetch: @ContactsActor (@escaping (Contact) -> Void) throws -> Void
    private let request: @ContactsActor () async throws -> Bool

    nonisolated convenience init(store: CNContactStore) {
        self.init(authorization: { CNContactStore.authorizationStatus(for: .contacts) },
                  fetch: { body in
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                body(Contact(contact))
            }
        }, request: { try await store.requestAccess(for: .contacts) })
    }

    nonisolated init(authorization: @escaping @Sendable () -> CNAuthorizationStatus,
                     fetch: @escaping @ContactsActor (@escaping (Contact) -> Void) throws -> Void,
                     request: @escaping @ContactsActor () async throws -> Bool) {
        self.authorization = authorization
        self.fetch = fetch
        self.request = request
    }

    func enumerate(_ body: @escaping (Contact) -> Void) -> Swift.Result<Void, ContactsLoadFailure> {
        if let failure = accessFailure { return .failure(failure) }
        var snapshot: [Contact] = []
        do {
            try fetch { snapshot.append($0) }
            // Never publish a partial fetch or contacts whose permission changed
            // while enumeration was in progress. No raw system error is logged.
            if let failure = accessFailure { return .failure(failure) }
            snapshot.forEach(body)
            return .success(())
        } catch {
            let systemError = error as NSError
            if systemError.domain == CNErrorDomain, systemError.code == CNError.Code.authorizationDenied.rawValue {
                return .failure(.denied)
            }
            if let failure = accessFailure { return .failure(failure) }
            return .failure(.transient)
        }
    }

    // Called only by the explicit Settings action, never by enumeration/rechecks.
    func requestAccessIfNeeded() async -> Bool {
        guard authorization() == .notDetermined else { return true }
        do { _ = try await request(); return true }
        catch { return false }
    }

    private var accessFailure: ContactsLoadFailure? {
        switch authorization() {
        case .authorized: return nil
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }
}

private let keys = [
    CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor
]
