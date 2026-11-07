//
//  CallHistoryViewEventTargetTests.swift
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
@testable import Telephone

@MainActor
final class CallHistoryViewEventTargetTests: XCTestCase {

    // MARK: - Should reload data

    func testExecutesCallHistoryRecordGetAllUseCaseOnShouldReloadData() {
        let get = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: get,
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.shouldReloadData()

        XCTAssertTrue(get.didCallExecute)
    }

    func testExecutesCallHistoryRecordGetAllUseCaseOnDidUpdateHistory() {
        let didExecuteRecordsGet = expectation(description: "Calls execute on records get")
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(callBack: didExecuteRecordsGet.fulfill),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.didUpdate(TruncatingCallHistory())

        wait(for: [didExecuteRecordsGet], timeout: 1)
    }

    func testExecutesCallHistoryRecordGetAllUseCaseOnDayDidChange() {
        let didExecuteRecordsGet = expectation(description: "Calls execute on records get")
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(callBack: didExecuteRecordsGet.fulfill),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.dayDidChange()

        wait(for: [didExecuteRecordsGet], timeout: 1)
    }

    func testExecutesCallHistoryRecordRemoveAllUseCaseOnShouldRemoveAllRecords() {
        let remove = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: remove,
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.shouldRemoveAllRecords()

        XCTAssertTrue(remove.didCallExecute)
    }

    // MARK: - Did pick record

    func testCreatesCallHistoryCallMakeUseCaseWithExpectedIdentifierOnDidPickRecord() {
        let factory = CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: factory
        )
        let identifier = "any"

        sut.didPickRecord(withIdentifier: identifier)

        XCTAssertEqual(factory.invokedIdentifier, identifier)
    }

    func testExecutesCallHistoryCallMakeUseCaseOnDidPickRecord() {
        let callMake = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: callMake)
        )

        sut.didPickRecord(withIdentifier: "any")

        XCTAssertTrue(callMake.didCallExecute)
    }

    // MARK: - Should remove record

    func testCreatesCallHistoryRecordRemoveUseCaseWithExpectedIdentifierOnShouldRemoveRecord() {
        let factory = CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy())
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: factory,
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )
        let identifier = "any"

        sut.shouldRemoveRecord(withIdentifier: identifier)

        XCTAssertEqual(factory.invokedIdentifier, identifier)
    }

    func testExecutesCallHistoryRecordRemoveUseCaseOnShouldRemoveRecord() {
        let remove = UseCaseSpy()
        let sut = CallHistoryViewEventTarget(
            recordsGet: UseCaseSpy(),
            recordRemoveAll: UseCaseSpy(),
            recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: remove),
            callMake: CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        )

        sut.shouldRemoveRecord(withIdentifier: "any")

        XCTAssertTrue(remove.didCallExecute)
    }
}

@MainActor
final class V30HistorySelectionTests: XCTestCase {
    private func record(_ id: String, name: String = "Synthetic") -> Telephone.PresentationCallHistoryRecord {
        Telephone.PresentationCallHistoryRecord(identifier: id, contact: Telephone.PresentationContact(title: name, tooltip: "", label: "", color: .labelColor, address: "synthetic"), date: "Today", duration: "00:01", isIncoming: false)
    }

    func testCappedNativeTableKeepsTheCallIdentityUsedByReturn() throws {
        let controller = Telephone.CallHistoryViewController(); _ = controller.view
        // Expanded history now enters through Search. Locate the actual table
        // independently so this regression still exercises record identity.
        let scroll = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? NSScrollView }.first)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let callFactory = CallHistoryCallMakeUseCaseFactorySpy(callMake: UseCaseSpy())
        let target = Telephone.CallHistoryViewEventTarget(recordsGet: UseCaseSpy(), recordRemoveAll: UseCaseSpy(), recordRemove: CallHistoryRecordRemoveUseCaseFactorySpy(remove: UseCaseSpy()), callMake: callFactory)
        controller.target = target
        let before = (0..<1000).map { record("R\($0)") }
        controller.show(before); table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        controller.show([record("NEW")] + before.dropLast())
        XCTAssertEqual(table.selectedRow, 2)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 0x24))
        controller.keyDown(with: event)
        XCTAssertEqual(callFactory.invokedIdentifier, "R1")
        // Identity is retained even when its displayed metadata changes.
        var refreshed = [record("NEW")] + Array(before.dropLast())
        refreshed[2] = record("R1", name: "Updated synthetic name")
        controller.show(refreshed); XCTAssertEqual(table.selectedRow, 2)
        controller.setHistoryExpanded(false); controller.show([record("LATEST")] + refreshed.dropLast())
        XCTAssertEqual(table.selectedRow, 0); XCTAssertEqual(table.numberOfRows, 1)
    }
}
