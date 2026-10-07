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

@MainActor
final class CallHistoryViewPresenterTests: XCTestCase {
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
        isIncoming: record.isIncoming
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
