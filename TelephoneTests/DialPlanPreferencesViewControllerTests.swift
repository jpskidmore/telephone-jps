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

    func testCountryCoverageFollowsAllFiveDraftProfilesInLightAndDarkWithoutResizingControls() throws {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 292),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = fixture.controller
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let page: NSSegmentedControl = try control("DialPlanPage", in: fixture.controller.view)
        page.selectedSegment = 1
        send(page)
        let hint: NSTextField = try control("DialPlanRouteCoverage", in: fixture.controller.view)
        let button: NSButton = try control("ShowDialPlanPrefixes", in: fixture.controller.view)
        let routeKeys = ["mobile", "landline", "international", "premium", "other", "service"]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for country in Telephone.DialPlanStore.supportedCountryCodes {
                try pick(country, identifier: "DialPlanCountry", in: fixture.controller)
                let expected = country == "+44"
                    ? "Mobile/Landline/Premium: UK ranges. Longest active prefix wins."
                    : "UK-only Mobile/Landline/Premium; \(country) domestic telephone numbers use Other."
                XCTAssertEqual(hint.stringValue, expected)
                XCTAssertEqual(hint.accessibilityValue() as? String, expected)
                XCTAssertEqual(hint.accessibilityLabel(), "Domestic number classification")
                let help = try XCTUnwrap(hint.toolTip)
                XCTAssertEqual(hint.accessibilityHelp(), help)
                XCTAssertTrue(help.contains("Numbers outside \(country) are International."))
                XCTAssertTrue(help.contains("Short/service codes and protected exact emergencies retain their separate rules."))
                XCTAssertTrue(help.contains("The longest matching active prefix wins."))
                XCTAssertTrue(help.contains("Offline connections never silently fall back."))
                if country != "+44" {
                    XCTAssertTrue(help.contains("Domestic telephone numbers in \(country) use Other."))
                    XCTAssertTrue(help.contains("Mobile/Landline/Premium range classification is UK-only."))
                }
                XCTAssertEqual(hint.frame, NSRect(x: 0, y: 4, width: 516, height: 18))
                let renderedSize = (hint.stringValue as NSString).size(withAttributes: [.font: try XCTUnwrap(hint.font)])
                XCTAssertLessThanOrEqual(renderedSize.width, hint.bounds.width)
                XCTAssertLessThanOrEqual(renderedSize.height, hint.bounds.height)
                XCTAssertEqual(button.frame, NSRect(x: 380, y: 193, width: 136, height: 26))
                for (index, key) in routeKeys.enumerated() {
                    let menu: NSPopUpButton = try control("DialPlanTarget.\(key)", in: fixture.controller.view)
                    XCTAssertEqual(menu.frame, NSRect(x: 154, y: CGFloat(166 - index * 27), width: 362, height: 26))
                    XCTAssertEqual(menu.toolTip, help)
                    XCTAssertEqual(menu.accessibilityHelp(), help)
                    XCTAssertEqual(menu.cell?.accessibilityHelp(), help)
                }
                for index in 0..<4 {
                    page.selectedSegment = index
                    send(page)
                    XCTAssertEqual(fixture.controller.view.fittingSize, NSSize(width: 548, height: 292))
                }
                page.selectedSegment = 1
                send(page)
                try captureTransparencyIfRequested(fixture.controller.view, name: "routes-\(country.dropFirst())-\(name).png")
            }
        }
        XCTAssertEqual(fixture.store.configuration["countryCode"] as? String, "+44")
        XCTAssertNil(fixture.defaults.object(forKey: Telephone.DialPlanStore.settingsKey))
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

    func testLiteralPauseRecallGuidanceSurvivesReadyWaitingOfflineAndBlockedPreviews() throws {
        var current = accounts
        let fixture = makeFixture(accountProvider: { current })
        defer { fixture.clean() }
        try pick("local", identifier: "DialPlanTarget.defaultAccountUUID", in: fixture.controller)
        let field: NSTextField = try control("DialPlanTestNumber", in: fixture.controller.view)
        let route: NSTextField = try control("DialPlanRoutePreview", in: fixture.controller.view)
        let explanation: NSTextField = try control("DialPlanPreviewExplanation", in: fixture.controller.view)
        field.stringValue = "123R45P67"
        let limitation = "Pause/recall syntax is preserved for the selected connection; it is not converted into post-connect DTMF."
        for (state, message) in [("online", "Use Localphone."), ("registering", "Wait for Localphone to register."),
                                 ("offline", "Localphone is Offline. Bring it online to make this call; no other connection will be used.")] {
            current = [Telephone.DialPlanAccount(uuid: "local", name: "Localphone", enabled: true, availability: state), accounts[1]]
            fixture.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            XCTAssertEqual(route.stringValue, "Localphone · Service / Default")
            XCTAssertEqual(explanation.stringValue, "\(message) \(limitation)")
            XCTAssertEqual(explanation.toolTip, explanation.stringValue)
            XCTAssertEqual(explanation.accessibilityValue() as? String, explanation.stringValue)
            XCTAssertEqual(route.toolTip, "123R45P67\n\(explanation.stringValue)")
        }
        try pick("block", identifier: "DialPlanTarget.service", in: fixture.controller)
        XCTAssertEqual(route.stringValue, "Blocked · Service / Default")
        XCTAssertEqual(explanation.stringValue, "Blocked by the dialling plan. \(limitation)")
        XCTAssertEqual(explanation.toolTip, explanation.stringValue)
        XCTAssertEqual(explanation.accessibilityValue() as? String, explanation.stringValue)
        XCTAssertEqual(route.toolTip, "123R45P67\n\(explanation.stringValue)")
        let canonical: NSTextField = try control("DialPlanCanonicalPreview", in: fixture.controller.view)
        XCTAssertEqual(canonical.stringValue, "123R45P67")
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
        XCTAssertTrue(text.string.hasPrefix(Telephone.DialPlanStore.metadataVersion + "\nSaved country: +44\n"))
        XCTAssertTrue(text.string.contains("Supported home-country profiles: \(Telephone.DialPlanStore.supportedCountryCodes.joined(separator: ", "))."))
        XCTAssertTrue(text.string.contains("Offline numbering information; ranges do not establish provider prices, allocation or reachability."))
        for prefix in fixture.store.categoryPrefixes("mobile") { XCTAssertTrue(text.string.contains(prefix)) }
        let done: NSButton = try control("CloseDialPlanPrefixes", in: try XCTUnwrap(panel.contentView))
        done.performClick(nil)
    }

    func testPrefixDetailsUseEachSavedCountryDespiteAnUnsavedDraftAndWrapInBothAppearances() throws {
        let countries = Telephone.DialPlanStore.supportedCountryCodes
        for (index, country) in countries.enumerated() {
            let fixture = makeFixture()
            defer { fixture.clean() }
            var settings = fixture.store.configuration
            settings["countryCode"] = country
            settings["areaCode"] = ""
            try fixture.store.updateConfiguration(settings)
            let draftCountry = countries[(index + 1) % countries.count]
            try pick(draftCountry, identifier: "DialPlanCountry", in: fixture.controller)
            XCTAssertTrue(fixture.controller.hasUnsavedChanges)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 292),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentViewController = fixture.controller
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            let button: NSButton = try control("ShowDialPlanPrefixes", in: fixture.controller.view)
            button.performClick(nil)
            let panel = try XCTUnwrap(window.attachedSheet)
            let content = try XCTUnwrap(panel.contentView)
            let scroll = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
            let text: NSTextView = try control("DialPlanPrefixDetails", in: content)
            XCTAssertEqual(panel.title, "Guided prefixes for \(country)")
            XCTAssertEqual(panel.contentLayoutRect.size, NSSize(width: 484, height: 244))
            XCTAssertEqual(scroll.frame, NSRect(x: 16, y: 63, width: 452, height: 165))
            XCTAssertTrue(text.string.hasPrefix(Telephone.DialPlanStore.metadataVersion + "\nSaved country: \(country)\n"))
            XCTAssertFalse(text.string.contains("Saved country: \(draftCountry)"))
            if country == "+44" {
                XCTAssertTrue(text.string.contains("Domestic UK telephone ranges include Mobile, Landline and Premium classification."))
            } else {
                XCTAssertTrue(text.string.contains("Domestic telephone numbers in \(country) use Other. Mobile/Landline/Premium range classification is UK-only."))
            }
            XCTAssertTrue(text.string.contains("Short/service codes and protected exact emergencies retain their separate rules."))
            let categories = [("mobile", "Mobile"), ("landline", "Landline"), ("international", "International"),
                              ("premium", "Premium"), ("other", "Other numbers"), ("service", "Service codes")]
            let expectedPrefixes = categories.map { key, title in
                "\(title)\n\(fixture.store.categoryPrefixes(key).joined(separator: ", "))"
            }.joined(separator: "\n\n")
            XCTAssertTrue(text.string.hasSuffix(expectedPrefixes))
            XCTAssertEqual(text.accessibilityLabel(), "Actual guided route prefixes for the saved country")
            XCTAssertEqual(text.accessibilityHelp(), "This list uses the saved country. Save country changes to update it.")
            XCTAssertTrue(text.isSelectable)
            XCTAssertFalse(text.isEditable)
            XCTAssertFalse(text.isHorizontallyResizable)
            XCTAssertEqual(text.textContainer?.widthTracksTextView, true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                panel.appearance = NSAppearance(named: appearance)
                content.layoutSubtreeIfNeeded()
                let container = try XCTUnwrap(text.textContainer)
                let manager = try XCTUnwrap(text.layoutManager)
                manager.ensureLayout(for: container)
                XCTAssertLessThanOrEqual(manager.usedRect(for: container).width, container.size.width)
                XCTAssertEqual(window.contentLayoutRect.size, NSSize(width: 548, height: 292))
                try captureTransparencyIfRequested(content, name: "prefixes-\(country.dropFirst())-\(name).png")
            }
            XCTAssertEqual(fixture.store.configuration["countryCode"] as? String, country)
            XCTAssertTrue(fixture.controller.hasUnsavedChanges)
            let done: NSButton = try control("CloseDialPlanPrefixes", in: content)
            done.performClick(nil)
        }
    }

    func testPrefixDetailsDescribeDisplayedRepairCountryWithoutClaimingCorruptDataWasSaved() throws {
        for stored in [Data("malformed saved plan".utf8), Data("{\"schemaVersion\":99,\"countryCode\":\"+33\",\"areaCode\":\"\",\"defaultAccountUUID\":\"local\",\"emergencyAccountUUID\":\"\",\"categoryTargets\":{},\"rules\":[]}".utf8)] {
            let fixture = makeFixture(storedPlan: stored)
            defer { fixture.clean() }
            XCTAssertFalse(fixture.store.configurationError.isEmpty)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 292),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentViewController = fixture.controller
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            // Repair edits can already point elsewhere; the sheet still describes
            // the fallback display country until a valid plan is saved.
            try pick("+33", identifier: "DialPlanCountry", in: fixture.controller)
            let coverage: NSTextField = try control("DialPlanRouteCoverage", in: fixture.controller.view)
            XCTAssertTrue(coverage.stringValue.contains("+33"))
            let button: NSButton = try control("ShowDialPlanPrefixes", in: fixture.controller.view)
            button.performClick(nil)
            let panel = try XCTUnwrap(window.attachedSheet)
            let content = try XCTUnwrap(panel.contentView)
            let text: NSTextView = try control("DialPlanPrefixDetails", in: content)
            XCTAssertEqual(panel.title, "Guided prefixes for displayed +44")
            XCTAssertTrue(text.string.hasPrefix(Telephone.DialPlanStore.metadataVersion + "\nDisplayed country: +44\nSaved plan needs repair."))
            XCTAssertTrue(text.string.contains("Routing is blocked until you repair and save it."))
            XCTAssertTrue(text.string.contains(fixture.store.configurationError))
            XCTAssertFalse(text.string.contains("Saved country:"))
            XCTAssertEqual(text.accessibilityLabel(), "Guided route prefixes for the displayed repair country")
            XCTAssertEqual(text.accessibilityHelp(), "The saved plan needs repair. These prefixes describe the displayed country, not a valid saved plan.")
            XCTAssertTrue(content.subviews.compactMap { $0 as? NSTextField }.contains {
                $0.stringValue == "Repair and save the plan to update this list. Longest active prefix wins."
            })
            XCTAssertEqual(fixture.defaults.data(forKey: Telephone.DialPlanStore.settingsKey), stored)
            XCTAssertFalse(fixture.store.resolveDestination("07799414799", accounts: accounts).canDial)
            let done: NSButton = try control("CloseDialPlanPrefixes", in: content)
            done.performClick(nil)
        }
    }

    private struct Fixture {
        let domain: String
        let defaults: UserDefaults
        let store: Telephone.DialPlanStore
        let controller: Telephone.DialPlanPreferencesViewController
        func clean() { defaults.removePersistentDomain(forName: domain) }
    }

    private func makeFixture(accountProvider: (() -> [Telephone.DialPlanAccount])? = nil, storedPlan: Data? = nil) -> Fixture {
        let domain = "test.jps.guided-routes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        if let storedPlan { defaults.set(storedPlan, forKey: Telephone.DialPlanStore.settingsKey) }
        let store = Telephone.DialPlanStore(defaults: defaults)
        let controller = Telephone.DialPlanPreferencesViewController(store: store, accountProvider: accountProvider ?? { self.accounts })
        _ = controller.view
        return Fixture(domain: domain, defaults: defaults, store: store, controller: controller)
    }

    private func captureTransparencyIfRequested(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["JPS_ROUTING_TRANSPARENCY_CAPTURE_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name))
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
