import Cocoa
import XCTest
@testable import Telephone

@MainActor
final class DialPlanPreferencesViewControllerTests: XCTestCase {
    private let accounts = [
        DialPlanAccount(uuid: "local", name: "Localphone", enabled: true, availability: "online"),
        DialPlanAccount(uuid: "aa", name: "AA", enabled: true, availability: "online")
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
        XCTAssertEqual(DialPlanStore(defaults: fixture.defaults).configuration["defaultAccountUUID"] as? String, "local")
    }

    func testInvalidAreaSaveKeepsPreviousBytesAndUserDraft() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        try fixture.store.updateConfiguration(fixture.store.configuration)
        let bytes = fixture.defaults.data(forKey: DialPlanStore.settingsKey)
        let area: NSTextField = try control("DialPlanArea", in: fixture.controller.view)
        area.stringValue = "not-an-area"
        fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: area))
        let save: NSButton = try control("SaveDialPlan", in: fixture.controller.view)
        save.performClick(nil)
        XCTAssertEqual(fixture.defaults.data(forKey: DialPlanStore.settingsKey), bytes)
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
        XCTAssertNil(fixture.defaults.object(forKey: DialPlanStore.settingsKey))
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        XCTAssertTrue(route.stringValue.contains("Localphone"))
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
        XCTAssertNil(fixture.defaults.object(forKey: DialPlanStore.settingsKey))
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
        let store: DialPlanStore
        let controller: DialPlanPreferencesViewController
        func clean() { defaults.removePersistentDomain(forName: domain) }
    }

    private func makeFixture() -> Fixture {
        let domain = "test.jps.guided-routes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let store = DialPlanStore(defaults: defaults)
        let controller = DialPlanPreferencesViewController(store: store) { self.accounts }
        _ = controller.view
        return Fixture(domain: domain, defaults: defaults, store: store, controller: controller)
    }

    private func pick(_ value: String, identifier: String, in controller: DialPlanPreferencesViewController) throws {
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
