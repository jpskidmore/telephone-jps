import Cocoa
import XCTest
@testable import Telephone

@MainActor
final class DialPlanPreferencesViewControllerTests: XCTestCase {
    private let accounts = [
        Telephone.DialPlanAccount(uuid: "local", name: "Localphone", enabled: true, availability: "online"),
        Telephone.DialPlanAccount(uuid: "aa", name: "AA", enabled: true, availability: "online")
    ]

    func testPaneKeepsCompactDimensionsAndSixAccessibleNativeRouteSelectors() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        XCTAssertEqual(fixture.controller.view.fittingSize, NSSize(width: 548, height: 292))
        for category in ["mobile", "landline", "international", "premium", "other", "service"] {
            let menu: NSPopUpButton = try control("DialPlanTarget.\(category)", in: fixture.controller.view)
            XCTAssertFalse(menu.accessibilityLabel()?.isEmpty ?? true)
            XCTAssertEqual(menu.cell?.accessibilityLabel(), menu.accessibilityLabel())
            XCTAssertTrue(menu.itemArray.contains { ($0.representedObject as? String) == "block" })
        }
        let segments: NSSegmentedControl = try control("DialPlanPage", in: fixture.controller.view)
        XCTAssertEqual(segments.segmentCount, 4)
        for index in 0..<4 {
            segments.selectedSegment = index
            send(segments)
            XCTAssertEqual(fixture.controller.view.fittingSize.height, 292)
        }
    }

    func testSaveStoresStableDefaultAndExplicitEmergencyUUIDs() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        try pick("local", identifier: "DialPlanTarget.defaultAccountUUID", in: fixture.controller)
        try pick("aa", identifier: "DialPlanTarget.emergencyAccountUUID", in: fixture.controller)
        XCTAssertTrue(fixture.controller.hasUnsavedChanges)
        let save: NSButton = try control("SaveDialPlan", in: fixture.controller.view)
        save.performClick(nil)
        XCTAssertEqual(fixture.store.configuration["defaultAccountUUID"] as? String, "local")
        XCTAssertEqual(fixture.store.configuration["emergencyAccountUUID"] as? String, "aa")
        XCTAssertFalse(fixture.controller.hasUnsavedChanges)
        XCTAssertEqual(Telephone.DialPlanStore(defaults: fixture.defaults).configuration["defaultAccountUUID"] as? String, "local")
    }

    func testInvalidAreaSaveKeepsPreviousBytesAndUserDraft() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        try fixture.store.updateConfiguration(fixture.store.configuration)
        let bytes = fixture.defaults.data(forKey: Telephone.DialPlanStore.settingsKey)
        let area: NSTextField = try control("DialPlanArea", in: fixture.controller.view)
        area.stringValue = "not-an-area"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: area))
        let save: NSButton = try control("SaveDialPlan", in: fixture.controller.view)
        save.performClick(nil)
        XCTAssertEqual(fixture.defaults.data(forKey: Telephone.DialPlanStore.settingsKey), bytes)
        XCTAssertEqual(area.stringValue, "not-an-area")
        XCTAssertTrue(fixture.controller.hasUnsavedChanges)
        let status: NSTextField = try control("DialPlanSaveStatus", in: fixture.controller.view)
        XCTAssertFalse(status.stringValue.isEmpty)
        XCTAssertEqual(status.textColor, .systemRed)
    }

    func testTesterNormalisesMobileAndLocalNumbersWithoutSaving() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        try pick("local", identifier: "DialPlanTarget.defaultAccountUUID", in: fixture.controller)
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        let preview: NSTextField = try control("DialPlanCanonicalPreview", in: fixture.controller.view)
        for (input, canonical) in [("07799414799", "+447799414799"), ("242110", "+441442242110")] {
            field.stringValue = input
            fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            XCTAssertEqual(preview.stringValue, canonical)
        }
        XCTAssertNil(fixture.defaults.object(forKey: Telephone.DialPlanStore.settingsKey))
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        XCTAssertTrue(route.stringValue.contains("Localphone"))
    }

    func testEachRefreshUsesOneSnapshotForEveryMenuPreviewAndDeferredExceptionRow() throws {
        var calls = 0
        let fixture = makeFixture(accountProvider: {
            calls += 1
            return [Telephone.DialPlanAccount(uuid: "local", name: calls.isMultiple(of: 2) ? "Second" : "First", enabled: true, availability: "online")]
        })
        defer { fixture.clean() }
        XCTAssertEqual(calls, 1)
        var settings = fixture.store.configuration
        settings["defaultAccountUUID"] = "local"
        settings["rules"] = [["id": "snapshot-rule", "prefix": "+447799", "target": "local", "enabled": true, "comment": ""]]
        try fixture.store.updateConfiguration(settings)
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        field.stringValue = "07799414799"
        let before = calls
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(calls, before + 1)
        let expectedName = calls.isMultiple(of: 2) ? "Second" : "First"
        for key in ["defaultAccountUUID", "emergencyAccountUUID", "mobile", "landline", "international", "premium", "other", "service"] {
            let menu: NSPopUpButton = try control("DialPlanTarget.\(key)", in: fixture.controller.view)
            let item = try XCTUnwrap(menu.itemArray.first { ($0.representedObject as? String) == "local" })
            XCTAssertEqual(item.title, expectedName)
        }
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        let explanation: NSTextField = try control("DialPlanPreviewExplanation", in: fixture.controller.view)
        XCTAssertEqual(route.stringValue, "\(expectedName) · Prefix +447799")
        XCTAssertEqual(explanation.stringValue, "Use \(expectedName).")
        let table: NSTableView = try control("DialPlanExceptions", in: fixture.controller.view)
        let column = try XCTUnwrap(table.tableColumns.first { $0.identifier.rawValue == "target" })
        for _ in 0..<3 {
            let row = try XCTUnwrap(fixture.controller.tableView(table, viewFor: column, row: 0) as? NSTextField)
            XCTAssertEqual(row.stringValue, expectedName)
        }
        XCTAssertEqual(calls, before + 1, "Deferred table cells must reuse the displayed snapshot")
        let beforeAppearance = calls
        fixture.controller.viewWillAppear()
        XCTAssertEqual(calls, beforeAppearance + 1)
        XCTAssertEqual(route.stringValue, "\(calls.isMultiple(of: 2) ? "Second" : "First") · Prefix +447799")
    }

    func testAccountRenameOfflineAndRemovalRefreshWithoutDiscardingUnsavedDraft() throws {
        var current = accounts
        var calls = 0
        let fixture = makeFixture(accountProvider: { calls += 1; return current })
        defer { fixture.clean() }
        var settings = fixture.store.configuration
        settings["defaultAccountUUID"] = "local"
        try fixture.store.updateConfiguration(settings)
        let area: NSTextField = try control("DialPlanArea", in: fixture.controller.view)
        area.stringValue = "020"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: area))
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        field.stringValue = "07799414799"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let menu: NSPopUpButton = try control("DialPlanTarget.defaultAccountUUID", in: fixture.controller.view)
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        let explanation: NSTextField = try control("DialPlanPreviewExplanation", in: fixture.controller.view)
        current = [Telephone.DialPlanAccount(uuid: "local", name: "Renamed connection", enabled: true, availability: "online"), accounts[1]]
        let beforeRename = calls
        NotificationCenter.default.post(name: Notification.Name(Telephone.DialPlanStore.accountsChangeNotificationName), object: nil)
        XCTAssertEqual(calls, beforeRename + 1)
        XCTAssertEqual(menu.selectedItem?.title, "Renamed connection")
        XCTAssertEqual(route.stringValue, "Renamed connection · Mobile / Default")
        XCTAssertEqual(explanation.stringValue, "Use Renamed connection.")

        current = [Telephone.DialPlanAccount(uuid: "local", name: "Renamed connection", enabled: true, availability: "offline"), accounts[1]]
        let beforeOffline = calls
        NotificationCenter.default.post(name: Notification.Name("JPSAccountRoutingStateDidChangeNotification"), object: nil)
        XCTAssertEqual(calls, beforeOffline + 1)
        XCTAssertEqual(route.textColor, .systemRed)
        XCTAssertTrue(explanation.stringValue.contains("Renamed connection is Offline"))
        XCTAssertTrue(explanation.stringValue.contains("no other connection will be used"))

        current = [accounts[1]]
        NotificationCenter.default.post(name: Notification.Name(Telephone.DialPlanStore.accountsChangeNotificationName), object: nil)
        XCTAssertEqual(menu.selectedItem?.representedObject as? String, "local")
        XCTAssertEqual(menu.selectedItem?.title, "Missing connection")
        XCTAssertEqual(route.stringValue, "No connection · Mobile / Default")
        XCTAssertTrue(explanation.stringValue.contains("selected connection was removed"))
        XCTAssertEqual(area.stringValue, "020")
        XCTAssertEqual(fixture.store.configuration["areaCode"] as? String, "01442")
        XCTAssertTrue(fixture.controller.hasUnsavedChanges)
    }

    func testExternalPlanRefreshPreservesUnsavedDraftAndUsesOneFreshAccountSnapshot() throws {
        var calls = 0
        let fixture = makeFixture(accountProvider: { calls += 1; return self.accounts })
        defer { fixture.clean() }
        try pick("local", identifier: "DialPlanTarget.defaultAccountUUID", in: fixture.controller)
        let before = calls
        var external = fixture.store.configuration
        external["defaultAccountUUID"] = "aa"
        external["areaCode"] = "020"
        try fixture.store.updateConfiguration(external)
        XCTAssertEqual(calls, before + 1)
        let menu: NSPopUpButton = try control("DialPlanTarget.defaultAccountUUID", in: fixture.controller.view)
        let area: NSTextField = try control("DialPlanArea", in: fixture.controller.view)
        XCTAssertEqual(menu.selectedItem?.representedObject as? String, "local")
        XCTAssertEqual(area.stringValue, "01442")
        XCTAssertTrue(fixture.controller.hasUnsavedChanges)
        XCTAssertEqual(fixture.store.configuration["defaultAccountUUID"] as? String, "aa")
    }

    func testSaveRendersOneSnapshotDespiteItsSynchronousCommittedChangeNotification() throws {
        var calls = 0
        let fixture = makeFixture(accountProvider: { calls += 1; return self.accounts })
        defer { fixture.clean() }
        try pick("local", identifier: "DialPlanTarget.defaultAccountUUID", in: fixture.controller)
        let before = calls
        let save: NSButton = try control("SaveDialPlan", in: fixture.controller.view)
        save.performClick(nil)
        XCTAssertEqual(calls, before + 1)
        XCTAssertFalse(fixture.controller.hasUnsavedChanges)
        XCTAssertEqual(fixture.store.configuration["defaultAccountUUID"] as? String, "local")
    }

    func testAccountRefreshPreservesOpenExceptionFieldsAndMissingTarget() throws {
        var current = accounts
        var calls = 0
        let fixture = makeFixture(accountProvider: { calls += 1; return current })
        defer { fixture.clean() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 292),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = fixture.controller
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let add: NSButton = try control("AddDialPlanException", in: fixture.controller.view)
        add.performClick(nil)
        let content = try XCTUnwrap(window.attachedSheet?.contentView)
        let prefix: NSTextField = try control("ExceptionPrefix", in: content)
        let comment: NSTextField = try control("ExceptionComment", in: content)
        let target: NSPopUpButton = try control("ExceptionTarget", in: content)
        let enabled: NSButton = try control("ExceptionEnabled", in: content)
        prefix.stringValue = "07799"
        comment.stringValue = "Keep draft comment"
        enabled.state = .off
        target.select(try XCTUnwrap(target.itemArray.first { ($0.representedObject as? String) == "aa" }))
        current = [accounts[0], Telephone.DialPlanAccount(uuid: "aa", name: "Renamed AA", enabled: true, availability: "online")]
        let before = calls
        NotificationCenter.default.post(name: Notification.Name(Telephone.DialPlanStore.accountsChangeNotificationName), object: nil)
        XCTAssertEqual(calls, before + 1)
        XCTAssertEqual(target.selectedItem?.title, "Renamed AA")
        current = [accounts[0]]
        NotificationCenter.default.post(name: Notification.Name(Telephone.DialPlanStore.accountsChangeNotificationName), object: nil)
        XCTAssertEqual(target.selectedItem?.representedObject as? String, "aa")
        XCTAssertEqual(target.selectedItem?.title, "Missing connection")
        XCTAssertEqual(prefix.stringValue, "07799")
        XCTAssertEqual(comment.stringValue, "Keep draft comment")
        XCTAssertEqual(enabled.state, .off)
        XCTAssertFalse(fixture.controller.hasUnsavedChanges)
        let cancel: NSButton = try control("CancelException", in: content)
        cancel.performClick(nil)
    }

    func testPreviewShowsCompleteLiteralPauseRecallExplanationWithoutSaving() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        try pick("local", identifier: "DialPlanTarget.defaultAccountUUID", in: fixture.controller)
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        field.stringValue = "123R45P67"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let canonical: NSTextField = try control("DialPlanCanonicalPreview", in: fixture.controller.view)
        let explanation: NSTextField = try control("DialPlanPreviewExplanation", in: fixture.controller.view)
        let message = "Use Localphone. Pause/recall syntax is preserved for the selected connection; it is not converted into post-connect DTMF."
        XCTAssertEqual(canonical.stringValue, "123R45P67")
        XCTAssertEqual(explanation.stringValue, message)
        XCTAssertEqual(explanation.toolTip, message)
        XCTAssertEqual(explanation.accessibilityValue() as? String, message)
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        XCTAssertEqual(route.toolTip, "123R45P67\n\(message)")
        field.stringValue = ""
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertNil(route.toolTip)
        XCTAssertEqual(explanation.accessibilityValue() as? String, explanation.stringValue)
        XCTAssertEqual(explanation.toolTip, explanation.stringValue)
        XCTAssertFalse(explanation.stringValue.contains("post-connect DTMF"))
        field.stringValue = "123R45P67"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let area: NSTextField = try control("DialPlanArea", in: fixture.controller.view)
        area.stringValue = "invalid"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: area))
        XCTAssertEqual(canonical.stringValue, "Check the dial-plan fields")
        XCTAssertNil(route.toolTip)
        XCTAssertEqual(explanation.accessibilityValue() as? String, explanation.stringValue)
        XCTAssertEqual(explanation.toolTip, explanation.stringValue)
        XCTAssertFalse(explanation.stringValue.contains("post-connect DTMF"))
        XCTAssertNil(fixture.defaults.object(forKey: Telephone.DialPlanStore.settingsKey))
    }

    func testBlockedDraftAppearsInPreviewWithoutChangingSavedPlan() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        try pick("block", identifier: "DialPlanTarget.mobile", in: fixture.controller)
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        field.stringValue = "07799414799"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        XCTAssertTrue(route.stringValue.hasPrefix("Blocked"))
        XCTAssertEqual(route.textColor, .systemRed)
        XCTAssertNil((fixture.store.configuration["categoryTargets"] as? [String: String])?["mobile"])
        XCTAssertNil(fixture.defaults.object(forKey: Telephone.DialPlanStore.settingsKey))
    }

    func testEmergencyHasUnconfiguredChoiceAndCannotChooseBlock() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let menu: NSPopUpButton = try control("DialPlanTarget.emergencyAccountUUID", in: fixture.controller.view)
        XCTAssertEqual(menu.selectedItem?.title, "Not configured")
        XCTAssertFalse(menu.itemArray.contains { ($0.representedObject as? String) == "block" })
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        field.stringValue = "999"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let preview: NSTextField = try control("DialPlanCanonicalPreview", in: fixture.controller.view)
        XCTAssertEqual(preview.stringValue, "999")
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        XCTAssertEqual(route.textColor, .systemRed)
    }

    func testMissingSavedConnectionRemainsVisibleRatherThanChangingToFirstAccount() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        var settings = fixture.store.configuration
        settings["defaultAccountUUID"] = "removed-account"
        try fixture.store.updateConfiguration(settings)
        fixture.controller.viewWillAppear()
        let menu: NSPopUpButton = try control("DialPlanTarget.defaultAccountUUID", in: fixture.controller.view)
        XCTAssertEqual(menu.selectedItem?.representedObject as? String, "removed-account")
        XCTAssertEqual(menu.selectedItem?.title, "Missing connection")
        XCTAssertFalse(fixture.controller.hasUnsavedChanges)
    }

    func testPreferencesNavigationAddsDialPlanWithoutResizingOtherPanes() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let preferences = PreferencesController(windowNibName: "Preferences")
        preferences.dialPlanStore = fixture.store
        preferences.dialPlanAccountProvider = { self.accounts }
        let window = try XCTUnwrap(preferences.window)
        let original = window.frame.size
        preferences.changeView(preferences.dialPlanToolbarItem)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame.size, original)
        XCTAssertEqual(window.title, "Dial plan")
        XCTAssertTrue(preferences.dialPlanPreferencesViewController.view.window === window)
        preferences.changeView(preferences.generalToolbarItem)
        XCTAssertEqual(window.frame.size, original)
        window.orderOut(nil)
    }

    func testExceptionEditorValidatesCommentAndCanonicalDuplicateBeforeChangingDraft() async throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 292),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = fixture.controller
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let add: NSButton = try control("AddDialPlanException", in: fixture.controller.view)
        add.performClick(nil)
        let editor = try XCTUnwrap(window.attachedSheet)
        let content = try XCTUnwrap(editor.contentView)
        let prefix: NSTextField = try control("ExceptionPrefix", in: content)
        let comment: NSTextField = try control("ExceptionComment", in: content)
        let target: NSPopUpButton = try control("ExceptionTarget", in: content)
        let accept: NSButton = try control("AcceptException", in: content)
        prefix.stringValue = "07799"
        target.select(try XCTUnwrap(target.itemArray.first { ($0.representedObject as? String) == "aa" }))
        comment.stringValue = String(repeating: "x", count: 21)
        accept.performClick(nil)
        XCTAssertFalse(fixture.controller.hasUnsavedChanges)
        let error: NSTextField = try control("ExceptionValidationMessage", in: content)
        XCTAssertFalse(error.stringValue.isEmpty)
        comment.stringValue = "AA exception"
        let ended = expectation(description: "Native exception sheet finished")
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { _ in ended.fulfill() }
        accept.performClick(nil)
        XCTAssertTrue(fixture.controller.hasUnsavedChanges)
        await fulfillment(of: [ended], timeout: 2)
        NotificationCenter.default.removeObserver(observer)
        let save: NSButton = try control("SaveDialPlan", in: fixture.controller.view)
        save.performClick(nil)
        let records = try XCTUnwrap(fixture.store.configuration["rules"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["prefix"] as? String, "+447799")
        add.performClick(nil)
        let secondContent = try XCTUnwrap(window.attachedSheet?.contentView)
        let secondPrefix: NSTextField = try control("ExceptionPrefix", in: secondContent)
        let secondTarget: NSPopUpButton = try control("ExceptionTarget", in: secondContent)
        secondPrefix.stringValue = "+447799"
        secondTarget.select(try XCTUnwrap(secondTarget.itemArray.first { ($0.representedObject as? String) == "block" }))
        let secondAccept: NSButton = try control("AcceptException", in: secondContent)
        secondAccept.performClick(nil)
        XCTAssertFalse(fixture.controller.hasUnsavedChanges)
        let duplicateError: NSTextField = try control("ExceptionValidationMessage", in: secondContent)
        XCTAssertTrue(duplicateError.stringValue.contains("already used"))
        let cancel: NSButton = try control("CancelException", in: secondContent)
        cancel.performClick(nil)
    }

    func testLightAndDarkCompactPagesFitAndExportSyntheticSnapshots() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let preferences = PreferencesController(windowNibName: "Preferences")
        preferences.dialPlanStore = fixture.store
        preferences.dialPlanAccountProvider = { self.accounts }
        let window = try XCTUnwrap(preferences.window)
        preferences.changeView(preferences.dialPlanToolbarItem)
        let pane = preferences.dialPlanPreferencesViewController
        let segments: NSSegmentedControl = try control("DialPlanPage", in: pane.view)
        let number: NSTextField = try control("DialPlanTestNumber", in: pane.view)
        number.stringValue = "242110"
        pane.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: number))
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JPS_GUI_SNAPSHOT_DIRECTORY"] ?? "/private/tmp/jps-guided-routes-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for index in 0..<4 {
                segments.selectedSegment = index
                send(segments)
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                XCTAssertEqual(window.frame.width, 592)
                XCTAssertEqual(window.frame.height, 337)
                let content = try XCTUnwrap(window.contentView)
                let paneFrame = pane.view.convert(pane.view.bounds, to: content)
                XCTAssertTrue(content.bounds.contains(paneFrame))
                XCTAssertEqual(pane.view.bounds.size, NSSize(width: 548, height: 292))
                let representation = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: representation)
                let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 100)
                try png.write(to: directory.appendingPathComponent("guided-routes-\(name)-\(index).png"))
            }
        }
    }

    func testPrefixDetailsUseBoundedNativeScrollableSheetAndActualBackendMetadata() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 292),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = fixture.controller
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let button: NSButton = try control("ShowDialPlanPrefixes", in: fixture.controller.view)
        button.performClick(nil)
        let panel = try XCTUnwrap(window.attachedSheet)
        XCTAssertLessThanOrEqual(panel.frame.width, 592)
        XCTAssertLessThanOrEqual(panel.frame.height, 337)
        let scroll = try XCTUnwrap(panel.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertTrue(scroll.hasVerticalScroller)
        let text = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertFalse(text.isEditable)
        for prefix in fixture.store.categoryPrefixes("mobile") { XCTAssertTrue(text.string.contains(prefix)) }
        let done: NSButton = try control("CloseDialPlanPrefixes", in: try XCTUnwrap(panel.contentView))
        done.performClick(nil)
    }

    private struct Fixture {
        let domain: String
        let defaults: UserDefaults
        let store: Telephone.DialPlanStore
        let controller: Telephone.DialPlanPreferencesViewController
        func clean() { defaults.removePersistentDomain(forName: domain) }
    }

    private func makeFixture(accountProvider: (() -> [Telephone.DialPlanAccount])? = nil) -> Fixture {
        let domain = "test.jps.guided-routes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let store = Telephone.DialPlanStore(defaults: defaults)
        let controller = Telephone.DialPlanPreferencesViewController(store: store, accountProvider: accountProvider ?? { self.accounts })
        _ = controller.view
        return Fixture(domain: domain, defaults: defaults, store: store, controller: controller)
    }

    private func pick(_ value: String, identifier: String, in controller: Telephone.DialPlanPreferencesViewController) throws {
        let menu: NSPopUpButton = try control(identifier, in: controller.view)
        menu.select(try XCTUnwrap(menu.itemArray.first { ($0.representedObject as? String) == value }))
        send(menu)
    }

    private func send(_ control: NSControl) {
        if let action = control.action { NSApplication.shared.sendAction(action, to: control.target, from: control) }
    }

    private func control<T: NSView>(_ identifier: String, in view: NSView) throws -> T {
        func find(_ candidate: NSView) -> T? {
            if candidate.identifier?.rawValue == identifier { return candidate as? T }
            return candidate.subviews.lazy.compactMap(find).first
        }
        return try XCTUnwrap(find(view), "Missing control \(identifier)")
    }
}
