//
//  CallHistoryCallMakeUseCase.swift
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

public final class CallHistoryCallMakeUseCase {
    private let account: Account?
    private let route: (@MainActor @Sendable (String, String, String) -> Void)?

    public init(account: Account) {
        self.account = account
        route = nil
    }

    public init(route: @escaping @MainActor @Sendable (String, String) -> Void) {
        account = nil
        self.route = { destination, label, _ in route(destination, label) }
    }

    public init(routeWithDisplayName: @escaping @MainActor @Sendable (String, String, String) -> Void) {
        account = nil
        route = routeWithDisplayName
    }
}

extension CallHistoryCallMakeUseCase: ContactCallHistoryRecordGetUseCaseOutput {
    public func update(record: ContactCallHistoryRecord) {
        Task {
            if let route {
                let name = record.contact.name.isEmpty ? record.origin.uri.displayName : record.contact.name
                await route(record.origin.callbackDestination, label(for: record.contact.address), name)
            } else if let account {
                await account.makeCall(to: URI(record: record), label: label(for: record.contact.address))
            }
        }
    }
}

private func label(for address: MatchedContact.Address) -> String {
    switch address {
    case let .phone(_, label), let .email(_, label):
        return label
    }
}
