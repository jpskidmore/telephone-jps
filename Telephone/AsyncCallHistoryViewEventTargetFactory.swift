//
//  AsyncCallHistoryViewEventTargetFactory.swift
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

import UseCases

@MainActor
final class AsyncCallHistoryViewEventTargetFactory: NSObject {
    private let origin: CallHistoryViewEventTargetFactory

    init(origin: CallHistoryViewEventTargetFactory) {
        self.origin = origin
    }

    @objc func make(account: Account, view: CallHistoryView, purchaseCheck: UseCase, completion: @escaping (CallHistoryViewEventTarget) -> Void) {
        Task {
            completion(await origin.make(account: account, view: view, purchaseCheck: purchaseCheck))
        }
    }

    @objc(makeGlobalWithAccounts:view:callDestinationHandler:completion:)
    func makeGlobal(accounts: [CallHistoryAccount], view: CallHistoryView,
                    callDestinationHandler: @escaping @MainActor @Sendable (String, String, String) -> Void,
                    completion: @escaping (CallHistoryViewEventTarget) -> Void) {
        let request = origin.prepareGlobalAccounts(accounts)
        Task {
            completion(await origin.makeGlobal(accounts: accounts, view: view, route: callDestinationHandler, request: request))
        }
    }

    @objc func updateGlobalAccounts(_ accounts: [CallHistoryAccount]) {
        // Reserve the generation synchronously before the actor hop. Rapid
        // rename/reorder events cannot let an older snapshot replace the latest.
        let request = origin.prepareGlobalAccounts(accounts)
        Task { await origin.applyGlobalAccounts(accounts, request: request) }
    }
}
