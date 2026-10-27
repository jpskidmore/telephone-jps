//
//  CallHistoryViewPresenter.swift
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

import Cocoa
import UseCases

@MainActor
final class CallHistoryViewPresenter {
    private let view: CallHistoryView
    private let dateFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter

    init(view: CallHistoryView, dateFormatter: DateFormatter, durationFormatter: DateComponentsFormatter) {
        self.view = view
        self.dateFormatter = dateFormatter
        self.durationFormatter = durationFormatter
    }
}

nonisolated extension CallHistoryViewPresenter: ContactCallHistoryRecordGetAllUseCaseOutput {
    func update(records: [ContactCallHistoryRecord]) async {
        await present(records: records, request: nil)
    }

    func update(records: [ContactCallHistoryRecord], request: CallHistoryReloadRequest) async {
        await present(records: records, request: request)
    }
}

private extension CallHistoryViewPresenter {
    func present(records: [ContactCallHistoryRecord], request: CallHistoryReloadRequest?) {
        // Check at the actual MainActor presentation hop, after Contacts/receipt awaits.
        guard request?.isCurrent != false else { return }
        view.show(records.map(makeRecord))
    }

    func makeRecord(from record: ContactCallHistoryRecord) -> PresentationCallHistoryRecord {
        PresentationCallHistoryRecord(
            identifier: record.origin.identifier,
            contact: PresentationContact(contact: record.contact, color: contactColor(for: record)),
            date: dateFormatter.string(from: record.origin.date),
            duration: durationFormatter.string(from: TimeInterval(record.origin.duration)) ?? "",
            isIncoming: record.origin.isIncoming,
            isMissed: record.origin.isMissed,
            accountUUID: record.origin.originAccountUUID,
            accountName: record.origin.originAccountName ?? "",
            recordingCallIdentifier: record.origin.recordingCallIdentifier
        )
    }
}

private func contactColor(for record: ContactCallHistoryRecord) -> NSColor {
    return record.origin.isMissed ? NSColor.systemRed : NSColor.controlTextColor
}
