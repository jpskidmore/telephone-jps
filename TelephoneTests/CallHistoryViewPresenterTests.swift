//
//  CallHistoryViewPresenterTests.swift
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
import UseCasesTestDoubles
import XCTest
import Cocoa
@testable import Telephone

@MainActor
final class CallHistoryViewPresenterTests: XCTestCase {
    func testHistoryStatusComesFromMissedAndIncomingFlagsIndependentlyOfColour() async {
        var displayed: [PresentationCallHistoryRecord] = []
        let sut = CallHistoryViewPresenter(view: CallHistoryViewSpy { displayed = $0 },
                                          dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter())
        let flags = [(true, true), (true, false), (false, false), (false, true)]
        let records = flags.map { incoming, missed in
            ContactCallHistoryRecord(origin: CallHistoryRecord(
                uri: URI(user: "synthetic", host: "example.invalid", displayName: "Synthetic"),
                date: Date(), duration: 0, isIncoming: incoming, isMissed: missed), contact: makeContact(number: 1))
        }

        await sut.update(records: records)

        XCTAssertEqual(displayed.map(\.status), [.missed, .incoming, .outgoing, .missed])
        XCTAssertEqual(displayed.map { $0.status.accessibilityValue }, ["Missed", "Incoming", "Outgoing", "Missed"])
        XCTAssertEqual(displayed.map(\.isIncoming), [true, true, false, false])
        XCTAssertEqual(displayed.map { $0.contact.color }, [.systemRed, .controlTextColor, .controlTextColor, .systemRed])
    }

    func testStatusOnlyChangeRecomparesPresentationWithoutChangingHistoryIdentity() {
        let contact = makePresentationContact(contact: makeContact(number: 1), color: .labelColor)
        let incoming = PresentationCallHistoryRecord(identifier: "same", contact: contact, date: "Today", duration: "0 sec", isIncoming: true)
        let missed = PresentationCallHistoryRecord(identifier: "same", contact: contact, date: "Today", duration: "0 sec", isIncoming: true, isMissed: true)
        XCTAssertEqual(incoming.identifier, missed.identifier)
        XCTAssertNotEqual(incoming, missed)
        XCTAssertEqual(Set([incoming, missed]).count, 2)
    }

    func testAccountBadgeUsesConfiguredFirstGraphemeAndFullNameInsteadOfHardcodedLetters() async {
        var displayed: [PresentationCallHistoryRecord] = []
        let sut = CallHistoryViewPresenter(view: CallHistoryViewSpy { displayed = $0 },
                                          dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter())
        let base = CallHistoryRecordTestFactory().makeRecord(number: 1)
        let records = [base.qualified(accountUUID: "a", accountName: "  First provider"),
                       base.qualified(accountUUID: "b", accountName: "Second provider"),
                       base.qualified(accountUUID: "c", accountName: "👩🏽‍💻 Office")]
        await sut.update(records: records.map { ContactCallHistoryRecord(origin: $0, contact: makeContact(number: 1)) })
        XCTAssertEqual(displayed.map(\.accountBadge), ["F", "S", "👩🏽‍💻"])
        XCTAssertEqual(displayed.map(\.accountUUID), ["a", "b", "c"])
        XCTAssertEqual(displayed[0].accountName, "  First provider")
        XCTAssertEqual(Set(displayed.map(\.identifier)).count, 3)
        await sut.update(records: [ContactCallHistoryRecord(origin: base.qualified(accountUUID: "a", accountName: "Primary"), contact: makeContact(number: 1))])
        XCTAssertEqual(displayed[0].accountBadge, "P")
        XCTAssertEqual(displayed[0].identifier, records[0].identifier)
    }
    func testShowsRecordsOnRecordsUpdate() async {
        let factory = CallHistoryRecordTestFactory()
        let record1 = factory.makeRecord(number: 1)
        let record2 = factory.makeRecord(number: 2)
        let contact1 = makeContact(number: 1)
        let contact2 = makeContact(number: 2)
        let didCallShow = expectation(description: "Did call show on view")
        var invokedRecords: [PresentationCallHistoryRecord]?
        let view = CallHistoryViewSpy { records in
            invokedRecords = records
            didCallShow.fulfill()
        }
        let sut = CallHistoryViewPresenter(
            view: view, dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter()
        )
        let expected1 = makePresentationCallHistoryRecord(contact: contact1, record: record1)
        let expected2 = makePresentationCallHistoryRecord(contact: contact2, record: record2)

        await sut.update(
            records: [
                ContactCallHistoryRecord(origin: record1, contact: contact1),
                ContactCallHistoryRecord(origin: record2, contact: contact2)
            ]
        )

        await fulfillment(of: [didCallShow], timeout: 1)
        XCTAssertEqual(invokedRecords, [expected1, expected2])
    }

    func testContactColorIsSystemRedForMissedCallRecords() async {
        let record = CallHistoryRecord(
            uri: URI(user: "any-user", host: "any-host", displayName: "any-name"),
            date: Date(),
            duration: 0,
            isIncoming: false,
            isMissed: true
        )
        let contact = makeContact(number: 1)
        let didCallShow = expectation(description: "Did call show on view")
        var invokedRecords: [PresentationCallHistoryRecord]?
        let view = CallHistoryViewSpy { records in
            invokedRecords = records
            didCallShow.fulfill()
        }
        let sut = CallHistoryViewPresenter(
            view: view, dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter()
        )

        await sut.update(records: [ContactCallHistoryRecord(origin: record, contact: contact)])

        await fulfillment(of: [didCallShow], timeout: 1)
        XCTAssertEqual(invokedRecords!.first!.contact.color, NSColor.systemRed)
    }

    func testTitleIsEmailAddressOrPhoneNumberAndTooltipIsEmptyWhenNameIsEmpty() async {
        let factory = CallHistoryRecordTestFactory()
        let record1 = factory.makeRecord(number: 1)
        let record2 = factory.makeRecord(number: 2)
        let address = "any-address"
        let number = "any-number"
        let contact1 = MatchedContact(name: "", address: .email(address: address, label: "any-label-1"))
        let contact2 = MatchedContact(name: "", address: .phone(number: number, label: "any-label-2"))
        let didCallShow = expectation(description: "Did call show on view")
        var invokedRecords: [PresentationCallHistoryRecord]?
        let view = CallHistoryViewSpy { records in
            invokedRecords = records
            didCallShow.fulfill()
        }
        let sut = CallHistoryViewPresenter(
            view: view, dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter()
        )

        await sut.update(
            records: [
                ContactCallHistoryRecord(origin: record1, contact: contact1),
                ContactCallHistoryRecord(origin: record2, contact: contact2)
            ]
        )

        await fulfillment(of: [didCallShow], timeout: 1)
        XCTAssertEqual(invokedRecords![0].contact.title, address)
        XCTAssertTrue(invokedRecords![0].contact.tooltip.isEmpty)
        XCTAssertEqual(invokedRecords![1].contact.title, number)
        XCTAssertTrue(invokedRecords![1].contact.tooltip.isEmpty)
    }
    func testLatestReloadRemainsVisibleAfterAnOlderResultArrives() async {
        let generation = CallHistoryReloadGeneration()
        let old = generation.next()
        let latest = generation.next()
        var snapshots: [[PresentationCallHistoryRecord]] = []
        let sut = CallHistoryViewPresenter(view: CallHistoryViewSpy { snapshots.append($0) },
                                          dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter())
        await sut.update(records: [], request: latest)
        await sut.update(records: [ContactCallHistoryRecord(origin: CallHistoryRecordTestFactory().makeRecord(number: 1),
                                                             contact: makeContact(number: 1))], request: old)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(snapshots[0].isEmpty)
    }

}

private func makeContact(number: Int) -> MatchedContact {
    return MatchedContact(
        name: "any-name-\(number)", address: .email(address: "any-address\(number)", label: "any-label-\(number)")
    )
}

private func makePresentationCallHistoryRecord(contact: MatchedContact, record: CallHistoryRecord) -> PresentationCallHistoryRecord {
    return PresentationCallHistoryRecord(
        identifier: record.identifier,
        contact: makePresentationContact(contact: contact, color: contactColor(for: record)),
        date: ShortRelativeDateTimeFormatter().string(from: record.date),
        duration: DurationFormatter().string(from: TimeInterval(record.duration))!,
        isIncoming: record.isIncoming,
        isMissed: record.isMissed
    )
}

private func makePresentationContact(contact: MatchedContact, color: NSColor) -> PresentationContact {
    switch contact.address {
    case let .phone(number, label):
        return PresentationContact(title: contact.name, tooltip: number, label: label, color: color, address: number)
    case let .email(address, label):
        return PresentationContact(title: contact.name, tooltip: address, label: label, color: color, address: address)
    }
}

private func contactColor(for record: CallHistoryRecord) -> NSColor {
    return record.isMissed ? NSColor.systemRed : NSColor.controlTextColor
}

@MainActor
final class CompactCallHistoryViewControllerTests: XCTestCase {
    func testCompactHistoryShowsOneBoundRecentRowWithoutTruncatingTheDataset() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        sut.setHistoryExpanded(false)
        let records = makeRecords([1, 2, 3])
        sut.show(records)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(sut.recordCount, 3)
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(table.style, .plain)
        XCTAssertEqual(table.enclosingScrollView?.frame, NSRect(x: 8, y: 0, width: 352, height: 47))
        XCTAssertLessThanOrEqual(table.rect(ofRow: 0).maxY, 47)
        let cell = try XCTUnwrap(table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, records[0].contact.title)
        XCTAssertFalse(table.enclosingScrollView!.hasVerticalScroller)
    }

    func testExpansionRestoresFullHistoryAndPreviousSelection() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let records = makeRecords([1, 2, 3])
        sut.show(records)
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)

        sut.setHistoryExpanded(false)
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(table.selectedRow, 0)
        XCTAssertEqual(sut.tableView(table, objectValueFor: nil, row: 0) as? PresentationCallHistoryRecord, records[0])

        sut.setHistoryExpanded(true)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(table.selectedRow, 2)
        XCTAssertEqual(table.style, .plain)
        XCTAssertTrue(table.enclosingScrollView!.hasVerticalScroller)
    }

    func testCompactPrependShowsNewestRecordAndExpandsWithoutLosingOlderRecords() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        sut.setHistoryExpanded(false)
        let old = makeRecords([1, 2])
        let prepended = makeRecords([3, 4])
        sut.show(old)
        sut.show(prepended + old)

        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(sut.recordCount, 4)
        XCTAssertEqual(sut.tableView(table, objectValueFor: nil, row: 0) as? PresentationCallHistoryRecord, prepended[0])
        sut.setHistoryExpanded(true)
        XCTAssertEqual(table.numberOfRows, 4)
        XCTAssertEqual(sut.tableView(table, objectValueFor: nil, row: 3) as? PresentationCallHistoryRecord, old[1])
    }

    func testDeletingCompactRecentRecordRevealsNextRecordAndKeepsNativeRowCountConsistent() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let records = makeRecords([1, 2])
        sut.setHistoryExpanded(false)
        sut.show(records)
        sut.removeRecord(withIdentifier: records[0].identifier)

        XCTAssertEqual(sut.recordCount, 1)
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(sut.tableView(table, objectValueFor: nil, row: 0) as? PresentationCallHistoryRecord, records[1])
        sut.removeRecord(withIdentifier: records[1].identifier)
        XCTAssertEqual(sut.recordCount, 0)
        XCTAssertEqual(table.numberOfRows, 0)
    }

    func testConfirmationIdentitySurvivesPrependBeforeCompletion() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let old = makeRecords([1, 2])
        sut.show(old)
        // Capture exactly the identifier retained by the production sheet path.
        let confirmedIdentifier = old[1].identifier
        let recent = makeRecords([3])
        sut.show(recent + old)
        sut.removeRecord(withIdentifier: confirmedIdentifier)

        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(sut.tableView(table, objectValueFor: nil, row: 0) as? PresentationCallHistoryRecord, recent[0])
        XCTAssertEqual(sut.tableView(table, objectValueFor: nil, row: 1) as? PresentationCallHistoryRecord, old[0])
        // Another completion for an already removed identity is a no-op.
        sut.removeRecord(withIdentifier: confirmedIdentifier)
        XCTAssertEqual(table.numberOfRows, 2)
    }

    func testReturnDeleteAndMenusWithNoSelectionDoNotCallOrRemoveAnUnrelatedRecord() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let call = CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        let remove = CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy())
        let target = CallHistoryViewEventTarget(recordsGet: UseCaseSpy(), purchaseCheck: UseCaseSpy(),
                                              recordRemoveAll: UseCaseSpy(), recordRemove: remove, callMake: call)
        sut.target = target
        sut.setHistoryExpanded(false)
        let records = makeRecords([1, 2])
        sut.show(records)
        table.allowsEmptySelection = true
        table.deselectAll(nil)
        sut.keyDown(with: try keyEvent(code: 0x24, characters: "\r", window: window))
        sut.keyDown(with: try keyEvent(code: 0x33, characters: "\u{7f}", window: window))
        XCTAssertNil(call.invokedIdentifier)
        XCTAssertNil(remove.invokedIdentifier)
        XCTAssertFalse(sut.validateMenuItem(NSMenuItem(title: "Call", action: #selector(CallHistoryViewController.makeCall(_:)), keyEquivalent: "")))
        XCTAssertTrue(sut.validateMenuItem(NSMenuItem(title: "Clear Call History…", action: #selector(CallHistoryViewController.deleteAll(_:)), keyEquivalent: "")))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        sut.makeCall(table)
        XCTAssertEqual(call.invokedIdentifier, records[0].identifier)
    }

    func testCompactNativeLayoutAndBoundRowWorkInLightAndDarkAppearances() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        sut.setHistoryExpanded(false)
        sut.show(makeRecords([1, 2]))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(table.enclosingScrollView?.frame.size.height, 47)
            XCTAssertNotNil(table.rowView(atRow: 0, makeIfNecessary: true))
            XCTAssertNotNil(table.view(atColumn: 2, row: 0, makeIfNecessary: true))
            XCTAssertFalse(sut.view.hasAmbiguousLayout)
        }
    }

    func testHistoryKeepsTheSameInsetAndIconGridWhenExpanded() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        sut.show(makeRecords([1, 2]))
        for expanded in [false, true] {
            sut.setHistoryExpanded(expanded)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(table.style, .plain)
            XCTAssertEqual(table.enclosingScrollView?.frame.minX, 8)
            XCTAssertEqual(table.enclosingScrollView?.frame.maxX, 360)
            XCTAssertEqual(table.tableColumns[0].width, 44)
            let direction = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
            direction.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(direction.subviews.compactMap { $0 as? NSImageView }.first)
            XCTAssertEqual(image.frame.midX, direction.bounds.midX, accuracy: 0.5)
            XCTAssertEqual(table.numberOfRows, expanded ? 2 : 1)
        }
    }

    func testClearCallHistoryKeepsTheExistingValidatedRemovalAction() throws {
        let (sut, _, window) = try makeHistoryController()
        defer { window.close() }
        let item = try XCTUnwrap(sut.actionsMenu.items.first { $0.action == #selector(CallHistoryViewController.deleteAll(_:)) })
        XCTAssertEqual(item.title, "Clear Call History…")
        XCTAssertFalse(sut.validateMenuItem(item))
        sut.show(makeRecords([1, 2]))
        XCTAssertTrue(sut.validateMenuItem(item))
        XCTAssertTrue((item.target as? NSObject) === sut)
    }

    func testExpandedFilterFocusChainAndFixedWidthStayInsideHistoryArea() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        // The isolated controller receives the same history-area width as the
        // native 368-point shared dialler, without launching the real app.
        window.setContentSize(NSSize(width: 368, height: 211))
        let filterRow = try XCTUnwrap(sut.view.subviews.compactMap { $0 as? NSStackView }.first)
        let search = try XCTUnwrap(filterRow.arrangedSubviews.compactMap { $0 as? NSSearchField }.first)
        let popups = filterRow.arrangedSubviews.compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(popups.count, 2)
        let returnTarget = NSButton(frame: .zero)
        sut.updateNextKeyView(returnTarget)

        sut.setHistoryExpanded(true)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(sut.keyView === search)
        XCTAssertTrue(search.nextKeyView === popups[0])
        XCTAssertTrue(popups[0].nextKeyView === popups[1])
        XCTAssertTrue(popups[1].nextKeyView === table)
        XCTAssertTrue(table.nextKeyView === returnTarget)
        XCTAssertFalse(filterRow.isHidden)
        XCTAssertGreaterThanOrEqual(search.frame.width, 80)
        XCTAssertGreaterThanOrEqual(popups[1].frame.width, 130)
        XCTAssertLessThanOrEqual(filterRow.frame.maxX, sut.view.bounds.maxX)
        XCTAssertGreaterThanOrEqual(filterRow.frame.minX, sut.view.bounds.minX)
        XCTAssertLessThanOrEqual(table.enclosingScrollView!.frame.maxY, filterRow.frame.minY + 1)
        XCTAssertFalse(sut.view.hasAmbiguousLayout)

        sut.setHistoryExpanded(false)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(sut.keyView === table)
        XCTAssertTrue(filterRow.isHidden)
        XCTAssertEqual(try XCTUnwrap(table.enclosingScrollView).frame.maxY, sut.view.bounds.maxY, accuracy: 1)
    }

    func testExpandedFilteringNeverMovesActionsToAnotherRecordUUID() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let call = CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        let target = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(), purchaseCheck: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: call
        )
        sut.target = target
        let records = makeRecords([1, 2, 3])
        sut.show(records)
        XCTAssertTrue(table.allowsEmptySelection)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        let filterRow = try XCTUnwrap(sut.view.subviews.compactMap { $0 as? NSStackView }.first)
        let search = try XCTUnwrap(filterRow.arrangedSubviews.compactMap { $0 as? NSSearchField }.first)
        let changed = Notification(name: Notification.Name("SyntheticSearchChanged"), object: search)
        search.stringValue = records[0].contact.title
        sut.controlTextDidChange(changed)
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(table.selectedRow, -1, "A different row must not inherit the previous selection.")
        sut.makeCall(table)
        XCTAssertNil(call.invokedIdentifier)

        search.stringValue = ""
        sut.controlTextDidChange(changed)
        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(table.selectedRow, -1, "Clearing a filter must not silently select a call.")
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let incoming = makeRecords([4])
        sut.show(incoming + records)
        XCTAssertEqual(table.selectedRow, 3, "An inserted call must preserve the selected UUID.")
        sut.makeCall(table)
        XCTAssertEqual(call.invokedIdentifier, records[2].identifier)
    }

    func testExpandedCombinedAccountStatusAndNumericQueryFiltering() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        func record(_ id: String, _ name: String, _ number: String, _ account: String, missed: Bool) -> PresentationCallHistoryRecord {
            PresentationCallHistoryRecord(identifier: id,
                contact: PresentationContact(title: name, tooltip: number, label: "Mobile",
                                             color: .labelColor, address: number),
                date: "Today", duration: "0 sec", isIncoming: missed, isMissed: missed,
                accountUUID: account, accountName: "Provider " + account.uppercased())
        }
        let first = record("a1", "Alice", "07700 900123", "a", missed: true)
        let second = record("b1", "Alex", "07700 900456", "b", missed: true)
        let third = record("a2", "Charlie", "020 7946 0111", "a", missed: false)
        sut.show([first, second, third])
        XCTAssertEqual(table.numberOfRows, 3)
        let filters = try XCTUnwrap(sut.view.subviews.compactMap { $0 as? NSStackView }.first)
        let search = try XCTUnwrap(filters.arrangedSubviews.compactMap { $0 as? NSSearchField }.first)
        let selectors = filters.arrangedSubviews.compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(selectors.count, 2)
        let status = selectors[0], account = selectors[1]
        status.selectItem(at: 1)
        XCTAssertTrue(status.sendAction(try XCTUnwrap(status.action), to: status.target))
        XCTAssertEqual(table.numberOfRows, 2)
        account.selectItem(withTitle: "Provider A")
        XCTAssertTrue(account.sendAction(try XCTUnwrap(account.action), to: account.target))
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual((sut.tableView(table, objectValueFor: nil, row: 0) as? PresentationCallHistoryRecord)?.identifier,
                       first.identifier)
        XCTAssertEqual(account.toolTip, "Provider A")
        let changed = Notification(name: Notification.Name("SyntheticSearchChanged"), object: search)
        search.stringValue = "07700900123"
        sut.controlTextDidChange(changed)
        XCTAssertEqual(table.numberOfRows, 1, "Ignore phone-number punctuation.")
        search.stringValue = "Unknown123"
        sut.controlTextDidChange(changed)
        XCTAssertEqual(table.numberOfRows, 0, "A mixed text query must not match unrelated phone digits.")
        XCTAssertEqual(table.selectedRow, -1)
        search.stringValue = ""
        sut.controlTextDidChange(changed)
        account.selectItem(at: 0)
        XCTAssertTrue(account.sendAction(try XCTUnwrap(account.action), to: account.target))
        status.selectItem(at: 0)
        XCTAssertTrue(status.sendAction(try XCTUnwrap(status.action), to: status.target))
        XCTAssertEqual(table.numberOfRows, 3)
        sut.setHistoryExpanded(false)
        XCTAssertEqual(table.numberOfRows, 1)
    }

    func testHistoryModeCanBeSetBeforeItsViewAndTableAreLoaded() {
        let sut = CallHistoryViewController()
        XCTAssertFalse(sut.isViewLoaded)

        // SharedDialerController requests compact history before loading its nib.
        sut.setHistoryExpanded(false)
        XCTAssertFalse(sut.historyExpanded)
        XCTAssertFalse(sut.isViewLoaded, "Setting the initial mode must not load the nib.")
        sut.setHistoryExpanded(false)
        sut.setHistoryExpanded(true)
        XCTAssertTrue(sut.historyExpanded)
        XCTAssertFalse(sut.isViewLoaded)
    }

    func testAccountFilterKeepsDistinctUUIDsAndAllAccountsWhenNamesCollide() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let records = [("a", "Office"), ("b", "Office"), ("c", "All accounts")].map { uuid, name in
            PresentationCallHistoryRecord(identifier: "record-" + uuid,
                contact: PresentationContact(title: "Caller " + uuid, tooltip: "", label: "",
                                             color: .labelColor, address: uuid + "@example.invalid"),
                date: "Today", duration: "0 sec", isIncoming: true,
                accountUUID: uuid, accountName: name)
        }
        sut.show(records)
        let filters = try XCTUnwrap(sut.view.subviews.compactMap { $0 as? NSStackView }.first)
        let account = try XCTUnwrap(filters.arrangedSubviews.compactMap { $0 as? NSPopUpButton }.last)
        XCTAssertEqual(account.numberOfItems, 4)
        XCTAssertNil(account.item(at: 0)?.representedObject)
        XCTAssertEqual(account.item(at: 0)?.title, "All accounts")
        XCTAssertEqual(account.itemArray.filter { $0.title == "Office" }.count, 2)

        for uuid in ["a", "b", "c"] {
            let item = try XCTUnwrap(account.itemArray.first { $0.representedObject as? String == "uuid:" + uuid })
            account.select(item)
            XCTAssertTrue(account.sendAction(try XCTUnwrap(account.action), to: account.target))
            XCTAssertEqual(table.numberOfRows, 1)
            XCTAssertEqual((sut.tableView(table, objectValueFor: nil, row: 0) as? PresentationCallHistoryRecord)?.identifier,
                           "record-" + uuid)
        }

        // Rebuilding from a reordered snapshot retains the exact selected UUID.
        sut.show(Array(records.reversed()))
        XCTAssertEqual(account.selectedItem?.representedObject as? String, "uuid:c")
        XCTAssertEqual(table.numberOfRows, 1)
        account.selectItem(at: 0)
        XCTAssertTrue(account.sendAction(try XCTUnwrap(account.action), to: account.target))
        XCTAssertEqual(table.numberOfRows, 3)
    }

    func testExpandedHistoryNativeLayoutInLightAndDarkAtMinimumAndWiderWidths() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let records = (1...6).map { number in
            PresentationCallHistoryRecord(identifier: "visual-\(number)",
                contact: PresentationContact(title: "Synthetic caller \(number)", tooltip: "07700 900123",
                                             label: "Mobile", color: .labelColor, address: "07700 900123"),
                date: "Today", duration: "30 sec", isIncoming: true, isMissed: number == 2,
                accountUUID: "provider", accountName: "Synthetic office provider with a long name")
        }
        sut.show(records)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for width in [368.0, 520.0] {
                window.setContentSize(NSSize(width: width, height: 211))
                window.contentView?.layoutSubtreeIfNeeded()
                XCTAssertEqual(table.numberOfRows, 6)
                XCTAssertFalse(sut.view.hasAmbiguousLayout)
                let bitmap = try XCTUnwrap(sut.view.bitmapImageRepForCachingDisplay(in: sut.view.bounds))
                sut.view.cacheDisplay(in: sut.view.bounds, to: bitmap)
                let image = NSImage(size: sut.view.bounds.size)
                image.addRepresentation(bitmap)
                let attachment = XCTAttachment(image: image)
                attachment.name = "History-\(appearance.rawValue)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testNativeSearchCancelRestoresRowsWithinTheRemainingFilters() throws {
        let (sut, table, window) = try makeHistoryController()
        defer { window.close() }
        let records = [("Alice", "a", true), ("Alex", "a", true), ("Bob", "b", true), ("Carol", "a", false)].map { name, account, missed in
            PresentationCallHistoryRecord(identifier: name,
                contact: PresentationContact(title: name, tooltip: "", label: "", color: .labelColor,
                                             address: name.lowercased() + "@example.invalid"),
                date: "Today", duration: "0 sec", isIncoming: true, isMissed: missed,
                accountUUID: account, accountName: "Provider " + account.uppercased())
        }
        sut.show(records)
        let filters = try XCTUnwrap(sut.view.subviews.compactMap { $0 as? NSStackView }.first)
        let search = try XCTUnwrap(filters.arrangedSubviews.compactMap { $0 as? NSSearchField }.first)
        let selectors = filters.arrangedSubviews.compactMap { $0 as? NSPopUpButton }
        let status = try XCTUnwrap(selectors.first), account = try XCTUnwrap(selectors.last)
        status.selectItem(at: 1)
        XCTAssertTrue(status.sendAction(try XCTUnwrap(status.action), to: status.target))
        account.selectItem(withTitle: "Provider A")
        XCTAssertTrue(account.sendAction(try XCTUnwrap(account.action), to: account.target))
        search.stringValue = "Alice"
        sut.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(table.numberOfRows, 1)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        let cell = try XCTUnwrap(search.cell as? NSSearchFieldCell)
        try XCTUnwrap(cell.cancelButtonCell).performClick(search)

        XCTAssertEqual(search.stringValue, "")
        XCTAssertEqual(table.numberOfRows, 2, "Native cancellation must clear only the text filter.")
        XCTAssertEqual((sut.tableView(table, objectValueFor: nil, row: table.selectedRow) as? PresentationCallHistoryRecord)?.identifier,
                       "Alice", "Clearing search must preserve the selected record identity.")
        XCTAssertEqual(account.selectedItem?.representedObject as? String, "uuid:a")
        XCTAssertEqual(status.indexOfSelectedItem, 1)
    }

    private func makeHistoryController() throws -> (CallHistoryViewController, NSTableView, NSWindow) {
        let sut = CallHistoryViewController()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 368, height: 47),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = sut.view
        window.contentView?.layoutSubtreeIfNeeded()
        return (sut, try XCTUnwrap(findTable(in: sut.view)), window)
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
    }

    private func makeRecords(_ numbers: [Int]) -> [PresentationCallHistoryRecord] {
        numbers.map { number in
            let record = CallHistoryRecordTestFactory().makeRecord(number: number)
            return makePresentationCallHistoryRecord(contact: makeContact(number: number), record: record)
        }
    }

    private func keyEvent(code: UInt16, characters: String, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
}

@MainActor
final class GlobalHistoryNativePresentationTests: XCTestCase {
    func testNativeOriginBadgesHaveFullNameAccessibilityAndStayWithinCompactGridInLightAndDark() throws {
        let controller = Telephone.CallHistoryViewController()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 368, height: 47),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = controller.view
        controller.setHistoryExpanded(false)
        let table = try XCTUnwrap(findTable(controller.view))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for name in ["First provider", "Second provider", "👩🏽‍💻 Office"] {
                controller.show([record(identifier: "a|record", uuid: "a", name: name)])
                window.contentView?.layoutSubtreeIfNeeded()
                let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? Telephone.CallHistoryDirectionCellView)
                cell.layoutSubtreeIfNeeded()
                let badge = try XCTUnwrap(cell.subviews.compactMap { $0 as? Telephone.CallHistoryAccountBadgeView }.first)
                XCTAssertEqual(badge.toolTip, name)
                XCTAssertEqual(badge.accessibilityValue() as? String, name)
                XCTAssertEqual(badge.accessibilityLabel(), "Call account")
                XCTAssertEqual(badge.glyph, name.first.map { String($0).uppercased() })
                XCTAssertEqual(badge.frame.size, NSSize(width: 18, height: 18))
                XCTAssertTrue(cell.bounds.contains(badge.frame))
                XCTAssertEqual(table.tableColumns[0].width, 44)
                XCTAssertEqual(table.enclosingScrollView?.frame.height, 47)
                XCTAssertEqual(table.numberOfRows, 1)
                XCTAssertFalse(controller.view.hasAmbiguousLayout)
                let image = try XCTUnwrap(badge.bitmapImageRepForCachingDisplay(in: badge.bounds))
                badge.cacheDisplay(in: badge.bounds, to: image)
                XCTAssertGreaterThan(image.pixelsWide, 0)
                if name.first?.isASCII == true {
                    var dark = 0, light = 0
                    for x in 0..<image.pixelsWide {
                        for y in 0..<image.pixelsHigh {
                            guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.8 else { continue }
                            let brightness = (pixel.redComponent + pixel.greenComponent + pixel.blueComponent) / 3
                            if brightness < 0.3 { dark += 1 }
                            if brightness > 0.7 { light += 1 }
                        }
                    }
                    XCTAssertGreaterThan(dark, 3, "The inverted badge needs a dark component in \(appearance)")
                    XCTAssertGreaterThan(light, 3, "The inverted badge needs a light component in \(appearance)")
                }
            }
        }
    }

    func testQualifiedSelectionSurvivesEqualRecordsFromDifferentAccountsAndRename() throws {
        let controller = Telephone.CallHistoryViewController()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 368, height: 141),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = controller.view
        let table = try XCTUnwrap(findTable(controller.view))
        controller.show([record(identifier: "a|same", uuid: "a", name: "First"), record(identifier: "b|same", uuid: "b", name: "Second")])
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        controller.show([record(identifier: "b|new", uuid: "b", name: "Renamed"),
                         record(identifier: "a|same", uuid: "a", name: "First"), record(identifier: "b|same", uuid: "b", name: "Renamed")])
        XCTAssertEqual(table.selectedRow, 2)
        let selected = try XCTUnwrap(controller.tableView(table, objectValueFor: nil, row: 2) as? Telephone.PresentationCallHistoryRecord)
        XCTAssertEqual(selected.identifier, "b|same")
        XCTAssertEqual(selected.accountName, "Renamed")
        controller.removeRecord(withIdentifier: "a|same")
        XCTAssertEqual(controller.recordCount, 2)
        XCTAssertEqual((controller.tableView(table, objectValueFor: nil, row: 1) as? Telephone.PresentationCallHistoryRecord)?.identifier, "b|same")
    }

    private func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable($0) }.first
    }
    private func record(identifier: String, uuid: String, name: String) -> Telephone.PresentationCallHistoryRecord {
        Telephone.PresentationCallHistoryRecord(identifier: identifier,
            contact: Telephone.PresentationContact(title: "Contact", tooltip: "+441442123456", label: "home", color: .labelColor, address: "+441442123456"),
            date: "Today, 13:00", duration: "2 sec", isIncoming: false, accountUUID: uuid, accountName: name)
    }
}

@MainActor
final class CallHistoryStatusAccessibilityTests: XCTestCase {
    func testNativeWindowTreeExposesOneStatusAndSeparateAccountPerVisibleRowInLightAndDark() throws {
        let (controller, table, window) = try makeHistory()
        defer { window.close() }
        let records = [record("missed", incoming: true, missed: true, account: "First provider"),
                       record("incoming", incoming: true, account: "Second provider"),
                       record("outgoing", incoming: false, account: "Third provider")]
        controller.show(records)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for expanded in [true, false] {
                controller.setHistoryExpanded(expanded)
                window.contentView?.layoutSubtreeIfNeeded()
                for row in 0..<table.numberOfRows { _ = table.view(atColumn: 0, row: row, makeIfNecessary: true) }
                let elements = accessibilityTree(from: window)
                let statuses = elements.filter { $0.historyAXLabel() == "Call status" }
                let accounts = elements.filter { $0.historyAXLabel() == "Call account" }
                let visible = expanded ? records : Array(records.prefix(1))
                XCTAssertEqual(statuses.compactMap { $0.historyAXValue() as? String }.sorted(), visible.map { $0.status.accessibilityValue }.sorted())
                XCTAssertEqual(accounts.compactMap { $0.historyAXValue() as? String }.sorted(), visible.map(\.accountName).sorted())
                XCTAssertEqual(statuses.count, visible.count)
                XCTAssertEqual(accounts.count, visible.count)
                XCTAssertFalse(statuses.contains { status in accounts.contains { ($0 as AnyObject) === (status as AnyObject) } })
                let values = elements.compactMap { $0.historyAXValue() as? String }
                for value in ["Synthetic contact", "Today, 13:00", "0 sec"] {
                    XCTAssertTrue(values.contains(value), "Existing history content must remain reachable: \(value)")
                }
                XCTAssertEqual(table.tableColumns[0].width, 44)
                let direction = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? Telephone.CallHistoryDirectionCellView)
                direction.layoutSubtreeIfNeeded()
                let semanticStatus = try XCTUnwrap(direction.subviews.first { $0.identifier?.rawValue == "CallHistoryStatus" })
                XCTAssertEqual(semanticStatus.frame.size, NSSize(width: 12, height: 12))
                XCTAssertEqual(semanticStatus.frame.midX, direction.bounds.midX, accuracy: 0.5)
                let statusTop = direction.isFlipped ? semanticStatus.frame.minY : semanticStatus.frame.maxY
                let expectedTop = direction.isFlipped ? direction.bounds.minY + 9 : direction.bounds.maxY - 9
                XCTAssertEqual(statusTop, expectedTop, accuracy: 0.5)
                let arrow = try XCTUnwrap(direction.subviews.compactMap { $0 as? NSImageView }.first)
                XCTAssertTrue(arrow.isHidden)
                XCTAssertFalse(arrow.isAccessibilityElement())
                XCTAssertFalse(elements.contains { ($0 as AnyObject) === arrow || ($0 as AnyObject) === arrow.cell })
                XCTAssertFalse(elements.contains { $0.historyAXRole() as? String == NSAccessibility.Role.image.rawValue }, "The decorative arrow must not add a second status announcement.")
            }
        }
    }

    func testReusedNativeDirectionCellClearsStatusForNilAndForeignValuesWithoutChangingItsRole() throws {
        let (controller, table, window) = try makeHistory()
        defer { window.close() }
        controller.show([record("missed", incoming: true, missed: true, account: "First provider")])
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? Telephone.CallHistoryDirectionCellView)
        let semanticStatus = try XCTUnwrap(cell.subviews.first { $0.identifier?.rawValue == "CallHistoryStatus" })
        let nativeRole = cell.accessibilityRole()
        for (incoming, missed, status) in [(true, true, "Missed"), (true, false, "Incoming"), (false, false, "Outgoing")] {
            cell.setValue(record("reused", incoming: incoming, missed: missed, account: "Current provider"), forKey: "objectValue")
            let tree = accessibilityTree(from: table)
            XCTAssertEqual(tree.filter { $0.historyAXLabel() == "Call status" }.compactMap { $0.historyAXValue() as? String }, [status])
            XCTAssertEqual(tree.filter { $0.historyAXLabel() == "Call account" }.compactMap { $0.historyAXValue() as? String }, ["Current provider"])
            XCTAssertEqual(cell.accessibilityRole(), nativeRole)
        }
        // This adversarial reset is outside the table's model contract. Detach
        // the native arrow binding before injecting a foreign object so AppKit's
        // binding teardown does not retain KVO observations on that dictionary.
        for arrow in cell.subviews.compactMap({ $0 as? NSImageView }) { arrow.unbind(.hidden) }
        let resetValues: [Any?] = [nil, ["isIncoming": false] as NSDictionary]
        for value in resetValues {
            cell.setValue(value, forKey: "objectValue")
            XCTAssertNil(semanticStatus.historyAXLabel())
            XCTAssertNil(semanticStatus.historyAXValue())
            XCTAssertFalse(semanticStatus.isAccessibilityElement())
            XCTAssertTrue(semanticStatus.isHidden)
            XCTAssertFalse(accessibilityTree(from: table).contains { $0.historyAXLabel() == "Call status" || $0.historyAXLabel() == "Call account" })
        }
        cell.setValue(record("restored", incoming: true, account: "Restored provider"), forKey: "objectValue")
        XCTAssertEqual(accessibilityTree(from: table).filter { $0.historyAXLabel() == "Call status" }.compactMap { $0.historyAXValue() as? String }, ["Incoming"])
    }

    func testSameIdentityStatusUpdateAndPrependKeepSelectedCallSemanticsThroughCollapse() throws {
        let (controller, table, window) = try makeHistory()
        defer { window.close() }
        let first = record("first", incoming: false, account: "First provider")
        controller.show([first, record("selected", incoming: true, missed: true, account: "Second provider")])
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let updated = record("selected", incoming: true, account: "Second provider")
        controller.show([first, updated])
        try assertSelectedStatus("Incoming", identifier: "selected", controller: controller, table: table)
        controller.show([record("new", incoming: true, missed: true, account: "Third provider"), first, updated])
        XCTAssertEqual(table.selectedRow, 2)
        try assertSelectedStatus("Incoming", identifier: "selected", controller: controller, table: table)
        controller.setHistoryExpanded(false)
        try assertSelectedStatus("Missed", identifier: "new", controller: controller, table: table)
        controller.setHistoryExpanded(true)
        XCTAssertEqual(table.selectedRow, 2)
        try assertSelectedStatus("Incoming", identifier: "selected", controller: controller, table: table)
    }

    private func assertSelectedStatus(_ status: String, identifier: String, controller: Telephone.CallHistoryViewController, table: NSTableView) throws {
        let row = table.selectedRow
        XCTAssertEqual((controller.tableView(table, objectValueFor: nil, row: row) as? Telephone.PresentationCallHistoryRecord)?.identifier, identifier)
        _ = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? Telephone.CallHistoryDirectionCellView)
        let selectedRows = table.historyAXSelectedRows()
        XCTAssertEqual(selectedRows.count, 1)
        let selectedRow = try XCTUnwrap(selectedRows.first)
        let statuses = accessibilityTree(from: selectedRow).filter { $0.historyAXLabel() == "Call status" }
        XCTAssertEqual(statuses.compactMap { $0.historyAXValue() as? String }, [status])
    }

    private func makeHistory() throws -> (Telephone.CallHistoryViewController, NSTableView, NSWindow) {
        let controller = Telephone.CallHistoryViewController()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 368, height: 141), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.view
        window.contentView?.layoutSubtreeIfNeeded()
        func table(in view: NSView) -> NSTableView? {
            if let result = view as? NSTableView { return result }
            return view.subviews.lazy.compactMap { table(in: $0) }.first
        }
        return (controller, try XCTUnwrap(table(in: controller.view)), window)
    }

    private func record(_ id: String, incoming: Bool, missed: Bool = false, account: String) -> Telephone.PresentationCallHistoryRecord {
        Telephone.PresentationCallHistoryRecord(identifier: id,
            contact: Telephone.PresentationContact(title: "Synthetic contact", tooltip: "", label: "home", color: missed ? .systemRed : .labelColor, address: "synthetic"),
            date: "Today, 13:00", duration: "0 sec", isIncoming: incoming, isMissed: missed, accountUUID: account, accountName: account)
    }

    private func accessibilityTree(from root: Any) -> [any NSObjectProtocol] {
        guard let unignoredRoot = NSAccessibility.unignoredDescendant(of: root) else { return [] }
        var pending: [Any] = [unignoredRoot]
        var visited = Set<ObjectIdentifier>()
        var result: [any NSObjectProtocol] = []
        while let candidate = pending.popLast() {
            guard let element = candidate as? any NSObjectProtocol,
                  visited.insert(ObjectIdentifier(element as AnyObject)).inserted else { continue }
            result.append(element)
            let children = element.historyAXChildren()
            if ProcessInfo.processInfo.environment["JPS_HISTORY_STATUS_AX_DIAGNOSTICS"] == "1" {
                print("History AX:", type(of: element), "role:", element.historyAXRole() as Any,
                      "label:", element.historyAXLabel() as Any, "value:", element.historyAXValue() as Any,
                      "children:", children.count, "formal AX:", element is any NSAccessibilityProtocol)
            }
            pending.append(contentsOf: NSAccessibility.unignoredChildren(from: children))
        }
        return result
    }
}

private extension NSObjectProtocol {
    func historyAXLabel() -> String? { historyAXValue(for: "accessibilityLabel", legacy: .description) as? String }
    func historyAXValue() -> Any? { historyAXValue(for: "accessibilityValue", legacy: .value) }
    func historyAXChildren() -> [Any] { historyAXValue(for: "accessibilityChildren", legacy: .children) as? [Any] ?? [] }
    func historyAXSelectedRows() -> [Any] { historyAXValue(for: "accessibilitySelectedRows", legacy: .selectedRows) as? [Any] ?? [] }
    func historyAXRole() -> Any? { historyAXValue(for: "accessibilityRole", legacy: .role) }

    private func historyAXValue(for name: String, legacy attribute: NSAccessibility.Attribute) -> Any? {
        let selector = NSSelectorFromString(name)
        if responds(to: selector) { return perform(selector)?.takeUnretainedValue() }
        // AppKit's native NSTableRow/NSTableColumn wrappers use the public
        // attribute API. Do not skip those branches or bypass modern view labels.
        let legacySelector = NSSelectorFromString("accessibilityAttributeValue:")
        guard responds(to: legacySelector) else { return nil }
        return perform(legacySelector, with: attribute.rawValue)?.takeUnretainedValue()
    }
}

@MainActor
final class UKEnglishFormatterTests: XCTestCase {
    func testHistoryDateUsesUKDayMonthOrderAnd24HourTime() throws {
        let formatter = ShortRelativeDateTimeFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 12, day: 25, hour: 13, minute: 34)))

        let text = formatter.string(from: date)

        XCTAssertTrue(text.hasPrefix("25/12/2024"), text)
        XCTAssertTrue(text.contains("13:34"), text)
    }

    func testCallDurationUsesEnglishUnitNames() throws {
        let text = try XCTUnwrap(DurationFormatter().string(from: 3661))

        XCTAssertTrue(text.contains("hr"), text)
        XCTAssertTrue(text.contains("min"), text)
        XCTAssertTrue(text.contains("sec"), text)
    }
}

@MainActor
final class AvailabilityStatusRenderingTests: XCTestCase {
    func testOnlineAndOfflineRenderSemanticColoursInLightAndDark() throws {
        let (controller, popup, window) = try makeStatusController()
        defer { window.close() }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            var marks = [Set<Int>]()
            for (action, title, colour) in [
                ("showAvailableState", "Available", NSColor.systemGreen),
                ("showOfflineState", "Offline", NSColor.systemRed)
            ] {
                controller.perform(NSSelectorFromString(action))
                let image = try XCTUnwrap(popup.itemArray.first?.image)
                XCTAssertFalse(image.isTemplate)
                XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
                XCTAssertNil(popup.contentTintColor)
                XCTAssertEqual(popup.toolTip, title)
                XCTAssertEqual(popup.accessibilityValue() as? String, title)
                XCTAssertGreaterThan(try pixelCount(matching: colour, in: popup, appearance: window.appearance!), 20,
                                     "Actual rounded popup must draw \(title) in \(name)")
                XCTAssertEqual(popup.frame.size, NSSize(width: 44, height: 44))
                let mark = try foregroundMark(in: popup, appearance: window.appearance!)
                XCTAssertGreaterThan(mark.count, 4, "\(title) must retain its contrasting mark inside the coloured circle in \(name)")
                marks.append(mark)
            }
            XCTAssertGreaterThan(marks[0].symmetricDifference(marks[1]).count, 8,
                                 "Online checkmark and offline cross must remain distinguishable in \(name)")
        }
    }

    func testConnectingStaysNeutralAndControlTintCannotReplaceStatusColour() throws {
        let (controller, popup, window) = try makeStatusController()
        defer { window.close() }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            controller.perform(NSSelectorFromString("showConnectingState"))
            XCTAssertEqual(try pixelCount(matching: .systemGreen, in: popup, appearance: window.appearance!), 0)
            XCTAssertEqual(try pixelCount(matching: .systemRed, in: popup, appearance: window.appearance!), 0)
            XCTAssertEqual(popup.toolTip, NSLocalizedString("Connecting...", comment: ""))
            controller.perform(NSSelectorFromString("showAvailableState"))
            popup.contentTintColor = .systemBlue
            XCTAssertGreaterThan(try pixelCount(matching: .systemGreen, in: popup, appearance: window.appearance!), 20)
            XCTAssertEqual(try pixelCount(matching: .systemBlue, in: popup, appearance: window.appearance!), 0)
        }
    }

    private func makeStatusController() throws -> (NSWindowController, NSPopUpButton, NSWindow) {
        // Exercise the hosted production controller and its actual popup setup,
        // with no account/network model and no account preferences or SIP calls.
        let type = try XCTUnwrap(NSClassFromString("AccountWindowController") as? NSWindowController.Type)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 44, height: 44),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = type.init(window: window)
        let popupType = try XCTUnwrap(NSClassFromString("AKCompactAvailabilityPopUpButton") as? NSPopUpButton.Type)
        let popup = popupType.init(frame: .zero, pullsDown: true)
        popup.addItem(withTitle: "")
        popup.itemArray.first?.isHidden = true
        let imageView = NSImageView(frame: .zero)
        let group = try XCTUnwrap(controller.perform(NSSelectorFromString("compactAvailabilityViewWithPopUp:image:"),
                                                    with: popup, with: imageView)?.takeUnretainedValue() as? NSView)
        let root = try XCTUnwrap(window.contentView)
        root.addSubview(group)
        // Production gives the popup group a required 44-point row. Preserve
        // that constraint instead of letting a window root use intrinsic size.
        NSLayoutConstraint.activate([
            group.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            group.topAnchor.constraint(equalTo: root.topAnchor),
            group.widthAnchor.constraint(equalToConstant: 44),
            group.heightAnchor.constraint(equalToConstant: 44)
        ])
        controller.setValue(popup, forKey: "accountStatePopUp")
        controller.setValue(imageView, forKey: "accountStateImageView")
        window.contentView?.layoutSubtreeIfNeeded()
        return (controller, popup, window)
    }

    private func pixelCount(matching colour: NSColor, in popup: NSPopUpButton, appearance: NSAppearance) throws -> Int {
        let image = try XCTUnwrap(popup.bitmapImageRepForCachingDisplay(in: popup.bounds))
        var expected: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            expected = colour.usingColorSpace(.sRGB)
            popup.cacheDisplay(in: popup.bounds, to: image)
        }
        let target = try XCTUnwrap(expected)
        var count = 0
        // Limit inspection to the drawn symbol, excluding native focus/bezel
        // colours which may follow the user's accent-colour preference.
        let glyph = try XCTUnwrap(popup.cell).imageRect(forBounds: popup.bounds)
        let sx = CGFloat(image.pixelsWide) / popup.bounds.width
        let sy = CGFloat(image.pixelsHigh) / popup.bounds.height
        let xs = max(0, Int(floor(glyph.minX * sx)))..<min(image.pixelsWide, Int(ceil(glyph.maxX * sx)))
        let ys = max(0, Int(floor(glyph.minY * sy)))..<min(image.pixelsHigh, Int(ceil(glyph.maxY * sy)))
        for y in ys {
            for x in xs {
                guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.7 else { continue }
                // Native material changes brightness/RGB. Require significant
                // glyph chroma; distinguish red from the existing orange state.
                let r = pixel.redComponent, g = pixel.greenComponent, b = pixel.blueComponent
                let matches: Bool
                if target.greenComponent > target.redComponent && target.greenComponent > target.blueComponent {
                    matches = g > r + 0.12 && g > b + 0.08
                } else if target.blueComponent > target.redComponent && target.blueComponent > target.greenComponent {
                    matches = b > r + 0.12 && b > g + 0.08
                } else {
                    matches = r > g + 0.12 && r > b + 0.08 && g - b < r - g
                }
                if matches { count += 1 }
            }
        }
        return count
    }

    private func foregroundMark(in popup: NSPopUpButton, appearance: NSAppearance) throws -> Set<Int> {
        let image = try XCTUnwrap(popup.bitmapImageRepForCachingDisplay(in: popup.bounds))
        appearance.performAsCurrentDrawingAppearance { popup.cacheDisplay(in: popup.bounds, to: image) }
        let glyph = try XCTUnwrap(popup.cell).imageRect(forBounds: popup.bounds)
        // Inspect only the inner circle: the bezel and the light background
        // beyond the circle cannot masquerade as the contrasting check/cross.
        let inner = glyph.insetBy(dx: glyph.width * 0.25, dy: glyph.height * 0.25)
        let sx = CGFloat(image.pixelsWide) / popup.bounds.width
        let sy = CGFloat(image.pixelsHigh) / popup.bounds.height
        let xs = max(0, Int(floor(inner.minX * sx)))..<min(image.pixelsWide, Int(ceil(inner.maxX * sx)))
        let ys = max(0, Int(floor(inner.minY * sy)))..<min(image.pixelsHigh, Int(ceil(inner.maxY * sy)))
        var mark = Set<Int>()
        for y in ys {
            for x in xs {
                guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.7 else { continue }
                if min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.85 {
                    mark.insert(y * image.pixelsWide + x)
                }
            }
        }
        return mark
    }
}
