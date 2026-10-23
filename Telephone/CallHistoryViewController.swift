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

private enum HistoryStatusFilter: Int {
    case all, missed, incoming, outgoing
}

final class CallHistoryViewController: NSViewController {
    // The dialler enters the filter controls before the table only when
    // expanded; compact history must never tab through hidden controls.
    @objc var keyView: NSView {
        _ = view
        return isExpanded ? searchField : tableView
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
    // The backing data is unchanged. Visible rows retain original record IDs.
    private var records: [PresentationCallHistoryRecord] = []
    private var visibleRecords: [PresentationCallHistoryRecord] = []
    private var statusFilter: HistoryStatusFilter = .all
    private var selectedAccountKey: String?
    private let searchField = NSSearchField(frame: .zero)
    private let statusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let accountPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var filterRow: NSStackView?
    private var compactScrollTop: NSLayoutConstraint?
    private var expandedScrollTop: NSLayoutConstraint?
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
        // Use one native row geometry in both modes so expanding the history
        // does not shift the direction icon and contact away from the dial bar.
        tableView.style = .plain
        // The XIB disables empty selection. Filtered-out rows must be able
        // to leave no selection rather than silently selecting another call.
        tableView.allowsEmptySelection = true
        tableView.setAccessibilityLabel(NSLocalizedString("Call history", comment: "Call history accessibility label."))
        configureFindControls()
        if let scroll = tableView.enclosingScrollView {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            compactScrollTop = scroll.topAnchor.constraint(equalTo: view.topAnchor)
            expandedScrollTop = scroll.topAnchor.constraint(equalTo: filterRow!.bottomAnchor, constant: 4)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
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

    private func configureFindControls() {
        searchField.placeholderString = NSLocalizedString("Find calls", comment: "Expanded call history search placeholder.")
        searchField.setAccessibilityLabel(NSLocalizedString("Find calls", comment: "Call history search accessibility label."))
        searchField.delegate = self
        // The native cancel button sends the field's action after clearing,
        // but does not send controlTextDidChange like ordinary typing does.
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusPopup.addItems(withTitles: [
            NSLocalizedString("All calls", comment: "History status filter."),
            NSLocalizedString("Missed", comment: "History status filter."),
            NSLocalizedString("Incoming", comment: "History status filter."),
            NSLocalizedString("Outgoing", comment: "History status filter.")
        ])
        statusPopup.setAccessibilityLabel(NSLocalizedString("Call type", comment: "History status selector."))
        statusPopup.toolTip = statusPopup.selectedItem?.title
        statusPopup.target = self
        statusPopup.action = #selector(statusFilterChanged(_:))

        accountPopup.setAccessibilityLabel(NSLocalizedString("Account", comment: "History account selector."))
        accountPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accountPopup.target = self
        accountPopup.action = #selector(accountFilterChanged(_:))
        rebuildAccountMenu()

        let row = NSStackView(views: [searchField, statusPopup, accountPopup])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            statusPopup.widthAnchor.constraint(equalToConstant: 90),
            accountPopup.widthAnchor.constraint(equalToConstant: 130)
        ])
        filterRow = row
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        refreshFilteredRows(keeping: selectedRecordIdentifier)
    }

    @objc private func statusFilterChanged(_ sender: NSPopUpButton) {
        statusPopup.toolTip = sender.selectedItem?.title
        statusFilter = HistoryStatusFilter(rawValue: sender.indexOfSelectedItem) ?? .all
        refreshFilteredRows(keeping: selectedRecordIdentifier)
    }

    @objc private func accountFilterChanged(_ sender: NSPopUpButton) {
        selectedAccountKey = sender.selectedItem?.representedObject as? String
        accountPopup.toolTip = sender.selectedItem?.title
        refreshFilteredRows(keeping: selectedRecordIdentifier)
    }

    // UUIDs distinguish accounts that share a display name. Older records
    // without UUIDs remain searchable using their stored account name.
    private func accountKey(for record: PresentationCallHistoryRecord) -> String {
        if let uuid = record.accountUUID { return "uuid:" + uuid }
        return "legacy:" + record.accountName
    }

    private func rebuildAccountMenu() {
        var names: [String: String] = [:]
        for record in records {
            let name = record.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
            names[accountKey(for: record)] = name.isEmpty
                ? NSLocalizedString("Unknown account", comment: "History record without an account name.")
                : name
        }
        accountPopup.removeAllItems()
        // The popup convenience API replaces an existing same-title item.
        // Insert menu items directly so account UUIDs and the unfiltered choice
        // stay distinct even when their displayed names are identical.
        let allAccounts = NSMenuItem(
            title: NSLocalizedString("All accounts", comment: "History account filter."),
            action: nil, keyEquivalent: ""
        )
        allAccounts.toolTip = allAccounts.title
        accountPopup.menu?.addItem(allAccounts)
        for (key, name) in names.sorted(by: {
            let order = $0.value.localizedStandardCompare($1.value)
            return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
        }) {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = key
            item.toolTip = name
            accountPopup.menu?.addItem(item)
        }
        if let key = selectedAccountKey,
           let index = (1..<accountPopup.numberOfItems).first(where: {
               accountPopup.item(at: $0)?.representedObject as? String == key
           }) {
            accountPopup.selectItem(at: index)
        } else {
            selectedAccountKey = nil
            accountPopup.selectItem(at: 0)
        }
        accountPopup.toolTip = accountPopup.selectedItem?.title
    }

    private func matchesFilters(_ record: PresentationCallHistoryRecord) -> Bool {
        switch statusFilter {
        case .all: break
        case .missed: guard record.status == .missed else { return false }
        case .incoming: guard record.status == .incoming else { return false }
        case .outgoing: guard record.status == .outgoing else { return false }
        }
        if let key = selectedAccountKey, key != accountKey(for: record) { return false }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return true }
        let texts = [record.contact.title, record.contact.tooltip, record.contact.address, record.accountName]
        if texts.contains(where: { $0.localizedStandardContains(query) }) { return true }
        // Compare phone numbers ignoring formatting, but only for numeric
        // queries. A mixed text query such as "Alice123" must not match an
        // unrelated telephone number simply because it contains "123".
        let phonePunctuation = CharacterSet(charactersIn: "+()-./")
        let isPhoneQuery = query.unicodeScalars.allSatisfy {
            CharacterSet.decimalDigits.contains($0)
                || CharacterSet.whitespaces.contains($0)
                || phonePunctuation.contains($0)
        }
        guard isPhoneQuery else { return false }
        let digits = String(query.filter { $0.isNumber })
        return !digits.isEmpty && texts.contains {
            String($0.filter { $0.isNumber }).contains(digits)
        }
    }

    private var selectedRecordIdentifier: String? {
        let row = tableView.selectedRow
        return visibleRecords.indices.contains(row) ? visibleRecords[row].identifier : nil
    }

    @objc func setHistoryExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        // The shared dialler sets compact mode before loading this controller's
        // nib. Remember that mode without touching the not-yet-connected table.
        guard isViewLoaded else {
            isExpanded = expanded
            return
        }
        if isExpanded {
            expandedSelectionIdentifier = selectedRecordIdentifier
        }
        // Preserve the compact row's identity on first expansion. On later
        // expansions, restore the prior expanded selection only if it exists.
        let selectionToRestore = expandedSelectionIdentifier ?? selectedRecordIdentifier
        isExpanded = expanded
        refreshFilteredRows(keeping: expanded ? selectionToRestore : nil)
    }

    private func refreshFilteredRows(keeping identifier: String?) {
        visibleRecords = isExpanded ? records.filter(matchesFilters) : Array(records.prefix(1))
        tableView.reloadData()
        if !isExpanded {
            // The compact presentation always shows its single newest call.
            if visibleRecords.isEmpty { tableView.deselectAll(nil) }
            else { selectVisibleRecord(at: 0) }
        } else if let identifier,
                  let row = visibleRecords.firstIndex(where: { $0.identifier == identifier }) {
            selectVisibleRecord(at: row)
        } else {
            // Never transfer a Call/Copy/Delete action to a different UUID
            // merely because filtering or a new arrival shifted row indexes.
            tableView.deselectAll(nil)
        }
        updateHistoryPresentation()
    }

    private func updateHistoryPresentation() {
        tableView.enclosingScrollView?.hasVerticalScroller = isExpanded
        filterRow?.isHidden = !isExpanded
        compactScrollTop?.isActive = false
        expandedScrollTop?.isActive = false
        (isExpanded ? expandedScrollTop : compactScrollTop)?.isActive = true
        emptyLabel?.stringValue = records.isEmpty
            ? NSLocalizedString("No recent calls", comment: "Empty call history.")
            : NSLocalizedString("No matching calls", comment: "No history records match the current filters.")
        emptyLabel?.isHidden = !visibleRecords.isEmpty
    }

    private func selectVisibleRecord(at index: Int) {
        guard !visibleRecords.isEmpty else { return }
        let visibleIndex = min(max(index, 0), visibleRecords.count - 1)
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
        // Search -> Status -> Account -> History -> Dialler, with the
        // collapsed dialler entering directly at History.
        searchField.nextKeyView = statusPopup
        statusPopup.nextKeyView = accountPopup
        accountPopup.nextKeyView = tableView
        tableView.nextKeyView = view
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
        let row = clickedOrSelectedRow()
        guard visibleRecords.indices.contains(row) else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects([visibleRecords[row]])
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

    // Resolve the original identifier after asynchronous confirmation.
    func removeRecord(withIdentifier identifier: String) {
        guard let row = records.firstIndex(where: { $0.identifier == identifier }) else { return }
        let selected = selectedRecordIdentifier
        records.remove(at: row)
        rebuildAccountMenu()
        refreshFilteredRows(keeping: selected == identifier ? nil : selected)
        target?.shouldRemoveRecord(withIdentifier: identifier)
    }
}

private extension CallHistoryViewController {
    func pickRecord(at index: Int) {
        guard visibleRecords.indices.contains(index) else { return }
        target?.didPickRecord(withIdentifier: visibleRecords[index].identifier)
    }

    func removeRecord(at index: Int) {
        guard visibleRecords.indices.contains(index) else { return }
        let record = visibleRecords[index]
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
        let previousSelection = selectedRecordIdentifier
        self.records = records
        rebuildAccountMenu()
        refreshFilteredRows(keeping: previousSelection)
    }
}

extension CallHistoryViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSSearchField) === searchField else { return }
        refreshFilteredRows(keeping: selectedRecordIdentifier)
    }
}

extension CallHistoryViewController: NSTableViewDataSource {
    func numberOfRows(in view: NSTableView) -> Int {
        return visibleRecords.count
    }

    func tableView(_ view: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        return visibleRecords[row]
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
        guard visibleRecords.indices.contains(row) else { return }
        removeRecord(withIdentifier: visibleRecords[row].identifier)
    }
}

extension CallHistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(deleteAll):
            return !records.isEmpty
        case #selector(copy(_:)), #selector(makeCall), #selector(delete):
            return visibleRecords.indices.contains(clickedOrSelectedRow())
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
