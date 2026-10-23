import Cocoa

// Inert boundary: these methods record dispatch only. No real use case, Contacts,
// credentials, defaults, history store, SIP stack, or pasteboard writes are used.
@MainActor final class CallHistoryViewEventTarget: NSObject {
    var picked: [String] = []
    var removed: [String] = []
    func shouldReloadData() {}
    func shouldRemoveAllRecords() {}
    func didPickRecord(withIdentifier identifier: String) { picked.append(identifier) }
    func shouldRemoveRecord(withIdentifier identifier: String) { removed.append(identifier) }
}

@main
@MainActor struct HistoryFilterRegressionHarness {
    private static var assertions = 0

    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("History filter regression failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if CommandLine.arguments.contains("--preload-only") {
            try verifyPreload()
            print("History preload regression passed (\(assertions) assertions).")
            return
        }
        if !CommandLine.arguments.contains("--menus-only") { try verifyPreload() }
        let fixture = Fixture()
        fixture.controller.show(records)
        try verifyMenus(fixture)
        if !CommandLine.arguments.contains("--menus-only") {
            try verifyFiltersAndIdentity(fixture)
            try verifyGeometry(fixture)
        }
        print("Native history filter regressions passed: \(assertions) assertions against the unchanged production controller, presentation records and contacts. Programmatic AppKit fixture; Xcode/nib, provider and VoiceOver acceptance remain separate.")
    }

    private static func verifyPreload() throws {
        let controller = CallHistoryViewController()
        try require(!controller.isViewLoaded, "Fixture must begin before the nib/view loads")
        controller.setHistoryExpanded(false)
        try require(!controller.isViewLoaded && !controller.historyExpanded, "Preload collapse must neither crash nor force nib loading")
        controller.setHistoryExpanded(true)
        controller.setHistoryExpanded(false)
        try require(!controller.isViewLoaded && !controller.historyExpanded, "Repeated preload transitions must remain safe")
    }

    private static var records: [PresentationCallHistoryRecord] {
        [record("a-missed", "Zoë García", "+44 (0)20 7946 0100", "uuid-a", "Shared", missed: true),
         record("b-incoming", "Béta Desk", "desk@example.test", "uuid-b", "Shared"),
         record("c-outgoing", "Carol", "01632 960123", "uuid-c", "All accounts", incoming: false),
         record("legacy", "Legacy Contact", "0300 123 4567", nil, "Legacy", incoming: false),
         record("blank", "Unknown Contact", "0300 111 2222", "uuid-blank", "  ")]
    }

    private static func record(_ id: String, _ name: String, _ address: String, _ uuid: String?, _ account: String,
                               incoming: Bool = true, missed: Bool = false) -> PresentationCallHistoryRecord {
        PresentationCallHistoryRecord(identifier: id,
            contact: PresentationContact(title: name, tooltip: address, label: "Work", color: .labelColor, address: address),
            date: "23 October 2026", duration: "00:30", isIncoming: incoming, isMissed: missed, accountUUID: uuid, accountName: account)
    }

    private static func verifyMenus(_ f: Fixture) throws {
        try require(f.accounts.numberOfItems == 6, "All accounts plus five distinct UUID/legacy keys must survive duplicate titles")
        let keys = f.accounts.itemArray.dropFirst().compactMap { $0.representedObject as? String }
        try require(Set(keys) == Set(["uuid:uuid-a", "uuid:uuid-b", "uuid:uuid-c", "legacy:Legacy", "uuid:uuid-blank"]),
                    "Every distinct account must retain its own represented UUID/legacy key")
        try require(f.accounts.item(at: 0)?.representedObject == nil, "All accounts sentinel must remain unfiltered after title collision")
        try require(f.accounts.itemArray.filter { $0.title == "Shared" }.count == 2, "Equal display names must remain separate menu entries")
        try require(f.accounts.itemArray.filter { $0.title == "All accounts" }.count == 2, "Account named All accounts must coexist with the sentinel")
        for (key, expected) in [("uuid:uuid-a", "a-missed"), ("uuid:uuid-b", "b-incoming"), ("uuid:uuid-c", "c-outgoing"), ("legacy:Legacy", "legacy"), ("uuid:uuid-blank", "blank")] {
            try f.selectAccount(key)
            try require(f.identifiers == [expected], "Account \(key) must filter by identity, independently of its displayed title")
            try require(f.accounts.toolTip == f.accounts.selectedItem?.title, "Selected account tooltip must match")
        }
        f.selectAllAccounts()
        try require(f.identifiers.count == records.count, "All accounts sentinel must restore all records")
    }

    private static func verifyFiltersAndIdentity(_ f: Fixture) throws {
        for (query, expected) in [("zoe garcia", ["a-missed"]), ("desk@example", ["b-incoming"]), ("0207946", ["a-missed"]),
                                  ("Shared", ["a-missed", "b-incoming"]), ("Carol123", []), ("  ", records.map(\.identifier))] {
            f.search(query)
            try require(f.identifiers == expected, "Query \(query.debugDescription) must match names, addresses, accounts and numeric formatting correctly")
        }
        f.search("")
        for (index, expected) in [(1, ["a-missed"]), (2, ["b-incoming", "blank"]), (3, ["c-outgoing", "legacy"])] {
            f.selectStatus(index)
            try require(f.identifiers == expected, "Call type index \(index) must show the correct statuses")
        }
        try f.selectAccount("uuid:uuid-c")
        f.search("960123")
        try require(f.identifiers == ["c-outgoing"], "Text, status and account filters must intersect")
        f.search("no matching call")
        try require(f.identifiers.isEmpty, "Native cancellation fixture must begin with no matching calls")
        try f.cancelSearchNatively()
        try require(f.searchField.stringValue.isEmpty, "Native cancel button must clear the query")
        try require(f.identifiers == ["c-outgoing"] && f.status.indexOfSelectedItem == 3
                    && f.accounts.selectedItem?.representedObject as? String == "uuid:uuid-c",
                    "Native cancel must restore results while preserving active account and type filters")
        try require(f.table.selectedRow == -1, "Native cancel must not silently transfer selection to a restored call")
        f.selectStatus(1)
        try require(f.identifiers.isEmpty && f.table.selectedRow == -1, "No-match filters must leave no selected/actionable row")
        try require(!f.controller.validateMenuItem(NSMenuItem(title: "Call", action: #selector(CallHistoryViewController.makeCall(_:)), keyEquivalent: "")), "Call must be disabled when no rows match")
        try require(f.emptyLabel?.stringValue == "No matching calls" && f.emptyLabel?.isHidden == false, "Filtered empty state must be visible")
        f.search(""); f.selectStatus(0); f.selectAllAccounts()
        f.search("no matching call")
        try require(f.identifiers.isEmpty, "Unfiltered cancellation fixture must begin with no matching calls")
        try f.cancelSearchNatively()
        try require(f.searchField.stringValue.isEmpty && f.identifiers == records.map(\.identifier),
                    "Native cancel with All accounts/All calls must restore all calls immediately")
        f.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        f.controller.makeCall(f.table)
        try require(f.target.picked.last == "b-incoming", "Call must dispatch the selected record identifier")
        let inserted = record("new", "New Arrival", "0118 496 0000", "uuid-new", "New")
        f.controller.show([inserted] + records)
        try require(f.selectedIdentifier == "b-incoming", "New arrival must preserve selection by identifier after row shift")
        f.controller.setHistoryExpanded(false)
        try require(f.identifiers == ["new"] && f.selectedIdentifier == "new", "Compact history must show and select its newest call")
        try require(f.controller.keyView === f.table && f.row.isHidden, "Compact keyboard entry must skip hidden filters")
        f.controller.setHistoryExpanded(true)
        try require(f.selectedIdentifier == "b-incoming" && f.controller.keyView === f.searchField, "Expansion must restore the prior expanded identity and search entry")
        f.search("Carol")
        try require(f.table.selectedRow == -1, "Filtering away selection must never silently select another call")
        f.controller.makeCall(f.table)
        try require(f.target.picked.count == 1, "No-selection Call must not dispatch a different row")
        f.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        f.controller.makeCall(f.table)
        try require(f.target.picked.last == "c-outgoing", "Filtered row zero must dispatch Carol's original identifier")
        f.search("")
        try f.selectAccount("uuid:uuid-b")
        f.controller.show(Array(records.reversed()))
        try require(f.identifiers == ["b-incoming"] && f.accounts.selectedItem?.representedObject as? String == "uuid:uuid-b", "Account identity must survive menu rebuild/reorder")
        f.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        f.controller.removeRecord(withIdentifier: "b-incoming")
        try require(f.target.removed == ["b-incoming"] && !f.identifiers.contains("b-incoming"), "Removal must dispatch the original identifier and remove its visible row")
        try require(f.accounts.selectedItem?.representedObject == nil, "Removing the final selected-account row must restore All accounts")
        try require(f.table.selectedRow == -1, "Removing selection must not silently retarget another record")
        f.controller.show([])
        try require(f.emptyLabel?.stringValue == "No recent calls" && f.emptyLabel?.isHidden == false, "True empty history must display its distinct message")
        let next = NSTextField()
        f.controller.updateNextKeyView(next)
        try require(f.searchField.nextKeyView === f.status && f.status.nextKeyView === f.accounts && f.accounts.nextKeyView === f.table && f.table.nextKeyView === next, "Native keyboard chain must visit all controls then return to the dialler")
    }

    private static func verifyGeometry(_ f: Fixture) throws {
        f.controller.show(records)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            f.root.appearance = NSAppearance(named: appearance)
            for width in [330.0, 460.0] {
                f.root.setFrameSize(NSSize(width: width, height: 220))
                f.controller.setHistoryExpanded(true)
                f.root.layoutSubtreeIfNeeded()
                try require(!f.row.isHidden && f.scroll.hasVerticalScroller, "Expanded \(appearance.rawValue) must show filters/scroller")
                try require(f.row.frame.minX >= 7.5 && f.row.frame.maxX <= width - 7.5, "Filter row must fit native \(width)-point width in \(appearance.rawValue)")
                try require(f.searchField.frame.width >= 79.5 && f.status.frame.width >= 89.5 && f.accounts.frame.width >= 129.5, "Controls must preserve minimum native widths")
                f.controller.setHistoryExpanded(false)
                f.root.layoutSubtreeIfNeeded()
                try require(f.row.isHidden && !f.scroll.hasVerticalScroller, "Compact \(appearance.rawValue) must hide filters/scroller")
            }
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        assertions += 1
        if !condition { throw NSError(domain: "HistoryFilterRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    // Actual native AppKit controls wired to the real controller. Only the nib's
    // view construction is replaced; all filtering, menu, selection and actions
    // run through unchanged production methods.
    @MainActor private final class Fixture {
        let controller = CallHistoryViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 220))
        let table = NSTableView()
        let scroll = NSScrollView()
        let target = CallHistoryViewEventTarget()
        var row: NSStackView { root.subviews.compactMap { $0 as? NSStackView }.first! }
        var searchField: NSSearchField { row.arrangedSubviews[0] as! NSSearchField }
        var status: NSPopUpButton { row.arrangedSubviews[1] as! NSPopUpButton }
        var accounts: NSPopUpButton { row.arrangedSubviews[2] as! NSPopUpButton }
        var emptyLabel: NSTextField? { root.subviews.compactMap { $0 as? NSTextField }.first }
        var identifiers: [String] { (0..<controller.numberOfRows(in: table)).map { (controller.tableView(table, objectValueFor: nil, row: $0) as! PresentationCallHistoryRecord).identifier } }
        var selectedIdentifier: String? { identifiers.indices.contains(table.selectedRow) ? identifiers[table.selectedRow] : nil }
        init() {
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history")))
            table.headerView = nil; table.rowHeight = 44
            scroll.documentView = table
            root.addSubview(scroll)
            controller.setValue(table, forKey: "tableView")
            table.dataSource = controller; table.delegate = controller
            controller.view = root
            if root.subviews.compactMap({ $0 as? NSStackView }).isEmpty { controller.viewDidLoad() }
            controller.target = target
        }
        func search(_ query: String) {
            searchField.stringValue = query
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        }
        func cancelSearchNatively() throws {
            guard let cancel = (searchField.cell as? NSSearchFieldCell)?.cancelButtonCell else {
                throw NSError(domain: "HistoryFilterRegression", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native search cancel button is unavailable"])
            }
            // Exercise AppKit's actual clear action. Do not synthesize the
            // delegate notification that this action does not ordinarily emit.
            cancel.performClick(searchField)
        }
        func selectStatus(_ index: Int) { status.selectItem(at: index); status.sendAction(status.action!, to: status.target) }
        func selectAllAccounts() { accounts.selectItem(at: 0); accounts.sendAction(accounts.action!, to: accounts.target) }
        func selectAccount(_ key: String) throws {
            guard let item = accounts.itemArray.first(where: { $0.representedObject as? String == key }) else {
                throw NSError(domain: "HistoryFilterRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing account key: \(key)"])
            }
            accounts.select(item); accounts.sendAction(accounts.action!, to: accounts.target)
        }
    }
}
