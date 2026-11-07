//
//  CallHistoryViewEventTargetFactory.swift
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
final class CallHistoryViewEventTargetFactory {
    private let histories: CallHistories
    private let index: ContactMatchingIndex
    private let settings: ContactMatchingSettings
    private let dateFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter
    private let dayChangeEventTargets: DayChangeEventTargets
    private let globalHistory: GlobalCallHistory
    private let accountCatalog: CallHistoryAccountCatalog
    private let accountGeneration = CallHistoryReloadGeneration()

    init(
        histories: CallHistories,
        index: ContactMatchingIndex,
        settings: ContactMatchingSettings,
        dateFormatter: DateFormatter,
        durationFormatter: DateComponentsFormatter,
        dayChangeEventTargets: DayChangeEventTargets,
        accountCatalog: CallHistoryAccountCatalog = CallHistoryAccountCatalog()
        ) {
        self.histories = histories
        self.index = index
        self.settings = settings
        self.dateFormatter = dateFormatter
        self.durationFormatter = durationFormatter
        self.dayChangeEventTargets = dayChangeEventTargets
        self.accountCatalog = accountCatalog
        globalHistory = GlobalCallHistory(histories: histories)
    }

    func make(account: Account, view: CallHistoryView) async -> CallHistoryViewEventTarget {
        let history = await histories.history(withUUID: account.uuid)
        let factory = FallingBackMatchedContactFactory(
            matching: IndexedContactMatching(
                index: index,
                significantPhoneNumberLength: await settings.significantPhoneNumberLength,
                domain: account.domain
            )
        )
        let result = CallHistoryViewEventTarget(
            recordsGet: CallHistoryRecordGetAllUseCase(
                history: history,
                output: ContactCallHistoryRecordGetAllUseCase(
                    factory: factory,
                    output: CallHistoryViewPresenter(
                        view: view, dateFormatter: dateFormatter, durationFormatter: durationFormatter
                    )
                )
            ),
            recordRemoveAll: CallHistoryRecordRemoveAllUseCase(history: history),
            recordRemove: DefaultCallHistoryRecordRemoveUseCaseFactory(history: history),
            callMake: DefaultCallHistoryCallMakeUseCaseFactory(account: account, history: history, factory: factory)
        )
        await history.updateTarget(WeakCallHistoryEventTarget(origin: result))
        dayChangeEventTargets.add(WeakDayChangeEventTarget(origin: result))
        return result
    }

    func prepareGlobalAccounts(_ accounts: [CallHistoryAccount]) -> CallHistoryReloadRequest {
        let request = accountGeneration.next()
        accountCatalog.update(accounts)
        return request
    }

    func applyGlobalAccounts(_ accounts: [CallHistoryAccount], request: CallHistoryReloadRequest) async {
        await globalHistory.updateAccounts(accounts, request: request)
    }

    func makeGlobal(accounts: [CallHistoryAccount], view: CallHistoryView,
                    route: @escaping @MainActor @Sendable (String, String, String) -> Void,
                    request preparedRequest: CallHistoryReloadRequest? = nil) async -> CallHistoryViewEventTarget {
        let request = preparedRequest ?? prepareGlobalAccounts(accounts)
        await applyGlobalAccounts(accounts, request: request)
        let factory = FallingBackMatchedContactFactory(
            matching: IndexedContactMatching(index: index,
                                            significantPhoneNumberLength: await settings.significantPhoneNumberLength,
                                            domain: "")
        )
        let result = CallHistoryViewEventTarget(
            recordsGet: CallHistoryRecordGetAllUseCase(
                history: globalHistory,
                output: ContactCallHistoryRecordGetAllUseCase(
                    factory: factory,
                    output: CallHistoryViewPresenter(view: view, dateFormatter: dateFormatter, durationFormatter: durationFormatter)
                )
            ),
            recordRemoveAll: CallHistoryRecordRemoveAllUseCase(history: globalHistory),
            recordRemove: DefaultCallHistoryRecordRemoveUseCaseFactory(history: globalHistory),
            callMake: DefaultCallHistoryCallMakeUseCaseFactory(history: globalHistory, factory: factory, route: route)
        )
        await globalHistory.updateTarget(WeakCallHistoryEventTarget(origin: result))
        dayChangeEventTargets.add(WeakDayChangeEventTarget(origin: result))
        return result
    }
}
