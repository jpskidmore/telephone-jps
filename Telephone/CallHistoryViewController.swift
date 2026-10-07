//
//  CallHistoryViewController.swift
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

final class CallHistoryViewController: NSViewController {
    @objc var keyView: NSView {
        return tableView
    }
    @objc weak var target: CallHistoryViewEventTarget? {
        didSet {
            target?.shouldReloadData()
        }
    }
    var recordCount: Int {
        return records.count
    }
    @objc var historyExpanded: Bool { isExpanded }
    @objc var actionsMenu: NSMenu {
        _ = view
        return tableView.menu!
    }
    private var isExpanded = true
    private var expandedSelectionIdentifier: String?
    private var emptyLabel: NSTextField?
    private var records: [PresentationCallHistoryRecord] = []
    private let pasteboard = NSPasteboard.general
    @IBOutlet private weak var tableView: NSTableView!

    init() {
        super.init(nibName: "CallHistoryViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.setAccessibilityLabel(NSLocalizedString("Call history", comment: "Call history accessibility label."))
        if let scroll = tableView.enclosingScrollView {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: view.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            let background = NSVisualEffectView(frame: view.bounds)
            background.material = .contentBackground
            background.blendingMode = .withinWindow
            background.state = .followsWindowActiveState
            background.autoresizingMask = [.width, .height]
            background.setAccessibilityElement(false)
            view.addSubview(background, positioned: .below, relativeTo: scroll)
            scroll.drawsBackground = false
            tableView.backgroundColor = .clear
        }
        let label = NSTextField(labelWithString: NSLocalizedString("No recent calls", comment: "Empty compact call history."))
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        emptyLabel = label
        updateHistoryPresentation()
        target?.shouldReloadData()
    }

    @objc func setHistoryExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if isViewLoaded, isExpanded, records.indices.contains(tableView.selectedRow) {
            expandedSelectionIdentifier = records[tableView.selectedRow].identifier
        }
        isExpanded = expanded
        guard isViewLoaded else { return }
        tableView.reloadData()
        let index = expanded ? records.firstIndex { $0.identifier == expandedSelectionIdentifier } ?? 0 : 0
        selectVisibleRecord(at: index)
        updateHistoryPresentation()
    }

    private func updateHistoryPresentation() {
        tableView.enclosingScrollView?.hasVerticalScroller = isExpanded
        emptyLabel?.isHidden = !records.isEmpty
    }

    private var visibleRecordCount: Int { isExpanded ? records.count : min(1, records.count) }

    private func selectVisibleRecord(at index: Int) {
        guard visibleRecordCount > 0 else { return }
        let visibleIndex = min(max(index, 0), visibleRecordCount - 1)
        tableView.selectRowIndexes(IndexSet(integer: visibleIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(visibleIndex)
    }

    override func keyDown(with event: NSEvent) {
        if isReturnKey(event) {
            pickRecord(at: tableView.selectedRow)
        } else if isDeleteKey(event) {
            removeRecord(at: tableView.selectedRow)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func updateNextKeyView(_ view: NSView) {
        keyView.nextKeyView = view
    }

    @IBAction func didDoubleClick(_ sender: NSTableView) {
        guard sender.clickedRow != -1 else { return }
        pickRecord(at: sender.clickedRow)
    }

    @IBAction func makeCall(_ sender: Any) {
        guard clickedOrSelectedRow() != -1 else { return }
        pickRecord(at: clickedOrSelectedRow())
    }

    @IBAction func copy(_ sender: Any) {
        guard records.indices.contains(clickedOrSelectedRow()), clickedOrSelectedRow() < visibleRecordCount else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects([records[clickedOrSelectedRow()]])
    }

    @IBAction func delete(_ sender: Any) {
        guard clickedOrSelectedRow() != -1 else { return }
        removeRecord(at: clickedOrSelectedRow())
    }

    @IBAction func deleteAll(_ sender: Any) {
        Task {
            if await makeDeleteAllAlert().beginSheetModal(for: view.window!) == .alertFirstButtonReturn {
                target?.shouldRemoveAllRecords()
            }
        }
    }

    // Resolve the identity again when an asynchronous confirmation completes.
    // A new call can prepend rows while the sheet is open.
    func removeRecord(withIdentifier identifier: String) {
        guard let row = records.firstIndex(where: { $0.identifier == identifier }) else { return }
        records.remove(at: row)
        if isExpanded {
            tableView.removeRows(at: IndexSet(integer: row), withAnimation: .slideUp)
        } else {
            // Removing the only visible row may reveal the next recent record;
            // an animated row removal would have an inconsistent row count.
            tableView.reloadData()
            selectVisibleRecord(at: 0)
        }
        updateHistoryPresentation()
        target?.shouldRemoveRecord(withIdentifier: identifier)
    }
}

private extension CallHistoryViewController {
    func pickRecord(at index: Int) {
        guard records.indices.contains(index), index < visibleRecordCount else { return }
        target?.didPickRecord(withIdentifier: records[index].identifier)
    }

    func removeRecord(at index: Int) {
        guard records.indices.contains(index), index < visibleRecordCount else { return }
        let record = records[index]
        Task {
            if await makeDeleteRecordAlert(recordName: record.name).beginSheetModal(for: view.window!) == .alertFirstButtonReturn {
                removeRecord(withIdentifier: record.identifier)
            }
        }
    }

    func isReturnKey(_ event: NSEvent) -> Bool {
        return event.keyCode == 0x24
    }

    func isDeleteKey(_ event: NSEvent) -> Bool {
        return event.keyCode == 0x33 || event.keyCode == 0x75
    }

    func clickedOrSelectedRow() -> Int {
        return tableView.clickedRow != -1 ? tableView.clickedRow : tableView.selectedRow
    }
}

extension CallHistoryViewController: CallHistoryView {
    func show(_ records: [PresentationCallHistoryRecord]) {
        let oldRecords = self.records
        let oldIndex = tableView.selectedRow
        self.records = records
        reloadTableView(old: oldRecords, new: records)
        restoreSelection(oldIndex: oldIndex, old: oldRecords, new: records)
        updateHistoryPresentation()
    }

    private func reloadTableView(old: [PresentationCallHistoryRecord], new: [PresentationCallHistoryRecord]) {
        guard isExpanded else {
            tableView.reloadData()
            return
        }
        let diff = ArrayDifference(before: old, after: new)
        if case .prepended(count: let count) = diff, count <= 2 {
            tableView.insertRows(at: IndexSet(integersIn: 0..<count), withAnimation: .slideDown)
        } else if case .shiftedByOne = diff {
            tableView.beginUpdates()
            tableView.insertRows(at: IndexSet(integer: 0), withAnimation: .slideDown)
            tableView.removeRows(at: IndexSet(integer: old.count), withAnimation: .slideDown)
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }
    }

    private func restoreSelection(oldIndex: Int, old: [PresentationCallHistoryRecord], new: [PresentationCallHistoryRecord]) {
        guard !records.isEmpty else { return }
        selectVisibleRecord(at: isExpanded ? RestoredSelectionIndex(indexBefore: oldIndex, before: old, after: new).value : 0)
    }
}

extension CallHistoryViewController: NSTableViewDataSource {
    func numberOfRows(in view: NSTableView) -> Int {
        return visibleRecordCount
    }

    func tableView(_ view: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        return records[row]
    }
}

extension CallHistoryViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSeparators()
    }

    func tableViewSelectionIsChanging(_ notification: Notification) {
        updateSeparators()
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        switch edge {
        case .trailing:
            return [makeDeleteAction()]
        case .leading:
            return []
        @unknown default:
            return []
        }
    }

    private func updateSeparators() {
        tableView.enumerateAvailableRowViews { (view, _) in
            view.needsDisplay = true
        }
    }

    private func makeDeleteAction() -> NSTableViewRowAction {
        let a = NSTableViewRowAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: "Delete button."),
            handler: removeRowAndRecord
        )
        a.image = NSImage(named: NSImage.touchBarDeleteTemplateName)
        return a
    }

    private func removeRowAndRecord(action: NSTableViewRowAction, row: Int) {
        guard records.indices.contains(row), row < visibleRecordCount else { return }
        removeRecord(withIdentifier: records[row].identifier)
    }
}

extension CallHistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(deleteAll):
            return !records.isEmpty
        case #selector(copy(_:)), #selector(makeCall), #selector(delete):
            return records.indices.contains(clickedOrSelectedRow()) && clickedOrSelectedRow() < visibleRecordCount
        default:
            return false
        }
    }
}

@MainActor
private func makeDeleteRecordAlert(recordName name: String) -> NSAlert {
    return makeDeletionAlert(
        messageText: String(
            format: NSLocalizedString(
                "Are you sure you want to delete the record “%@”?", comment: "Call history record removal alert."
            ),
            name
        )
    )
}

@MainActor
private func makeDeleteAllAlert() -> NSAlert {
    return makeDeletionAlert(
        messageText: NSLocalizedString(
            "Are you sure you want to delete all records?", comment: "Call history all records removal alert."
        )
    )
}

@MainActor
private func makeDeletionAlert(messageText text: String) -> NSAlert {
    let a = NSAlert()
    a.messageText = text
    a.informativeText = NSLocalizedString(
        "This action cannot be undone.", comment: "Call history record removal alert informative text."
    )
    let delete = a.addButton(withTitle: NSLocalizedString("Delete", comment: "Delete button."))
    delete.hasDestructiveAction = true
    a.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button.")).keyEquivalent = "\u{1b}"
    return a
}
