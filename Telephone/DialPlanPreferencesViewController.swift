import Cocoa

/// A fixed-size native editor for the same dial plan used by the shared dialler.
@MainActor
@objcMembers
final class DialPlanPreferencesViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store: DialPlanStore
    private let accountProvider: () -> [DialPlanAccount]
    // Retained only for one rendered state, including deferred table-cell asks.
    // Every refresh replaces it before any menu, row or preview is rebuilt.
    private var renderedAccounts: [DialPlanAccount] = []
    private var draft: [String: Any]
    private var saved: [String: Any]
    private var isSavingDraft = false
    private var pages: [NSView] = []
    private var selectors: [String: NSPopUpButton] = [:]
    private var exceptionEditor: NSWindow?
    private var prefixesSheet: NSWindow?
    private var editingRuleID: String?
    private var editorFields: [String: NSControl] = [:]

    private let segments = NSSegmentedControl(labels: ["Numbers", "Routes", "Exceptions", "Test"], trackingMode: .selectOne, target: nil, action: nil)
    private let areaField = NSTextField(string: "")
    private let numberExampleLabel = NSTextField(labelWithString: "")
    private let routeCoverageLabel = NSTextField(labelWithString: "")
    private let countryMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rulesTable = NSTableView()
    private let testField = NSTextField(string: "")
    private let canonicalLabel = NSTextField(wrappingLabelWithString: "")
    private let routeLabel = NSTextField(wrappingLabelWithString: "")
    private let previewMessage = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let categories: [(String, String)] = [
        ("mobile", "Mobile"), ("landline", "Landline"),
        ("international", "International"), ("premium", "Premium"),
        ("other", "Other numbers"), ("service", "Service codes")
    ]

    @objc(initWithStore:accountProvider:)
    init(store: DialPlanStore, accountProvider: @escaping () -> [DialPlanAccount]) {
        self.store = store
        self.accountProvider = accountProvider
        draft = store.configuration
        saved = store.configuration
        super.init(nibName: nil, bundle: nil)
        title = "Dial plan"
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(accountStateDidChange(_:)),
                           name: Notification.Name("JPSAccountRoutingStateDidChangeNotification"), object: nil)
        centre.addObserver(self, selector: #selector(accountStateDidChange(_:)),
                           name: Notification.Name(DialPlanStore.accountsChangeNotificationName), object: nil)
        centre.addObserver(self, selector: #selector(savedPlanDidChange(_:)),
                           name: Notification.Name(DialPlanStore.changeNotificationName), object: store)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc(initWithStore:defaults:)
    convenience init(store: DialPlanStore, defaults: UserDefaults) {
        self.init(store: store) {
            (defaults.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []).compactMap { values in
                guard let uuid = values[AKSIPAccountKeys.uuid] as? String else { return nil }
                let description = values[AKSIPAccountKeys.desc] as? String ?? ""
                let name = description.isEmpty ? values[AKSIPAccountKeys.sipAddress] as? String ?? "Connection" : description
                return DialPlanAccount(uuid: uuid, name: name,
                                       enabled: values[UserDefaultsKeys.accountEnabled] as? Bool ?? true,
                                       availability: "offline")
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(accountStateDidChange(_:)),
                                               name: UserDefaults.didChangeNotification, object: defaults)
    }

    required init?(coder: NSCoder) { fatalError("Use the injected dial-plan initializer") }

    var hasUnsavedChanges: Bool { !(draft as NSDictionary).isEqual(to: saved) }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 548, height: 292))
        root.identifier = NSUserInterfaceItemIdentifier("DialPlanPreferences")
        root.setAccessibilityLabel("Dial plan settings")
        view = root
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 548),
            root.heightAnchor.constraint(equalToConstant: 292)
        ])
        segments.frame = NSRect(x: 16, y: 260, width: 516, height: 24)
        segments.identifier = NSUserInterfaceItemIdentifier("DialPlanPage")
        segments.selectedSegment = 0
        segments.target = self
        segments.action = #selector(changePage(_:))
        segments.setAccessibilityLabel("Dial plan section")
        root.addSubview(segments)
        for _ in 0..<4 {
            let page = NSView(frame: NSRect(x: 16, y: 34, width: 516, height: 218))
            root.addSubview(page)
            pages.append(page)
        }
        buildNumbersPage(pages[0])
        buildRoutesPage(pages[1])
        buildExceptionsPage(pages[2])
        buildTestPage(pages[3])

        statusLabel.frame = NSRect(x: 16, y: 6, width: 428, height: 18)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.identifier = NSUserInterfaceItemIdentifier("DialPlanSaveStatus")
        root.addSubview(statusLabel)
        saveButton.frame = NSRect(x: 456, y: 3, width: 76, height: 26)
        saveButton.bezelStyle = .rounded
        saveButton.identifier = NSUserInterfaceItemIdentifier("SaveDialPlan")
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.setAccessibilityLabel("Save dial plan")
        root.addSubview(saveButton)
        refreshControls()
        changePage(segments)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if !hasUnsavedChanges { reloadSavedConfiguration() }
        else { refreshAccountPresentation() }
    }

    @objc nonisolated private func accountStateDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { refreshAccountPresentation() }
        } else {
            Task { @MainActor [weak self] in self?.refreshAccountPresentation() }
        }
    }

    @objc private func savedPlanDidChange(_ notification: Notification) {
        guard isViewLoaded, !isSavingDraft else { return }
        if hasUnsavedChanges { refreshAccountPresentation() }
        else { reloadSavedConfiguration() }
    }

    private func buildNumbersPage(_ page: NSView) {
        heading("Number format", in: page, y: 198)
        label("Country", in: page, x: 0, y: 167, width: 74)
        countryMenu.frame = NSRect(x: 78, y: 163, width: 244, height: 26)
        countryMenu.identifier = NSUserInterfaceItemIdentifier("DialPlanCountry")
        let countryNames = ["+44": "United Kingdom (+44)", "+1": "US / Canada (+1)",
                            "+33": "France (+33)", "+49": "Germany (+49)", "+39": "Italy (+39)"]
        for code in DialPlanStore.supportedCountryCodes {
            countryMenu.addItem(withTitle: countryNames[code] ?? code)
            countryMenu.lastItem?.representedObject = code
        }
        countryMenu.target = self
        countryMenu.action = #selector(countryChanged(_:))
        countryMenu.setAccessibilityLabel("Default country code")
        countryMenu.cell?.setAccessibilityLabel("Default country code")
        page.addSubview(countryMenu)
        label("Area", in: page, x: 336, y: 167, width: 40)
        textField(areaField, identifier: "DialPlanArea", label: "Local area code", frame: NSRect(x: 378, y: 165, width: 138, height: 23), in: page)
        areaField.toolTip = "Use the national area code, for example 01442. It is added to local numbers before routing."
        numberExampleLabel.frame = NSRect(x: 0, y: 139, width: 516, height: 18)
        numberExampleLabel.font = .systemFont(ofSize: 11)
        numberExampleLabel.textColor = .secondaryLabelColor
        numberExampleLabel.lineBreakMode = .byTruncatingTail
        page.addSubview(numberExampleLabel)

        heading("Default and emergency connections", in: page, y: 108)
        label("Default", in: page, x: 0, y: 78, width: 74)
        installSelector(key: "defaultAccountUUID", label: "Default outgoing connection", frame: NSRect(x: 78, y: 74, width: 244, height: 26), in: page)
        label("Used only when no active rule matches.", in: page, x: 0, y: 52, width: 516, secondary: true)
        label("Emergency", in: page, x: 0, y: 23, width: 74)
        installSelector(key: "emergencyAccountUUID", label: "Emergency call provider", frame: NSRect(x: 78, y: 19, width: 244, height: 26), in: page)
        label("Only choose a provider you know supports emergency calls.", in: page, x: 0, y: 0, width: 516, secondary: true)
    }

    private func buildRoutesPage(_ page: NSView) {
        heading("Outgoing connections", in: page, y: 198)
        let prefixes = button("Show prefixes…", action: #selector(showPrefixes(_:)), identifier: "ShowDialPlanPrefixes")
        prefixes.frame = NSRect(x: 380, y: 193, width: 136, height: 26)
        page.addSubview(prefixes)
        for (index, category) in categories.enumerated() {
            let y = CGFloat(166 - index * 27)
            label(category.1, in: page, x: 0, y: y + 4, width: 148)
            installSelector(key: category.0, label: "\(category.1) outgoing connection", frame: NSRect(x: 154, y: y, width: 362, height: 26), in: page)
        }
        routeCoverageLabel.frame = NSRect(x: 0, y: 4, width: 516, height: 18)
        routeCoverageLabel.font = .systemFont(ofSize: 11)
        routeCoverageLabel.textColor = .secondaryLabelColor
        routeCoverageLabel.identifier = NSUserInterfaceItemIdentifier("DialPlanRouteCoverage")
        routeCoverageLabel.setAccessibilityLabel("Domestic number classification")
        page.addSubview(routeCoverageLabel)
    }

    private func buildExceptionsPage(_ page: NSView) {
        heading("Custom exceptions", in: page, y: 198)
        label("More specific prefixes take precedence; duplicate prefixes are rejected.", in: page, x: 0, y: 179, width: 516, secondary: true)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 39, width: 516, height: 135))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        rulesTable.style = .plain
        rulesTable.identifier = NSUserInterfaceItemIdentifier("DialPlanExceptions")
        rulesTable.rowHeight = 24
        rulesTable.allowsMultipleSelection = false
        rulesTable.setAccessibilityLabel("Custom dial-plan exceptions")
        for (key, title, width) in [("enabled", "On", 32.0), ("prefix", "Prefix", 95.0),
                                    ("target", "Connection", 164.0), ("comment", "Comment", 195.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title
            column.width = width
            rulesTable.addTableColumn(column)
        }
        rulesTable.delegate = self
        rulesTable.dataSource = self
        rulesTable.doubleAction = #selector(editException(_:))
        rulesTable.target = self
        scroll.documentView = rulesTable
        page.addSubview(scroll)
        let actions: [(String, Selector, String, CGFloat)] = [
            ("+", #selector(addException(_:)), "AddDialPlanException", 0),
            ("−", #selector(removeException(_:)), "RemoveDialPlanException", 32),
            ("Edit…", #selector(editException(_:)), "EditDialPlanException", 72)
        ]
        for (title, selector, identifier, x) in actions {
            let control = button(title, action: selector, identifier: identifier)
            control.frame = NSRect(x: x, y: 4, width: title == "Edit…" ? 82 : 30, height: 26)
            control.setAccessibilityLabel(identifier == "AddDialPlanException" ? "Add exception" : identifier == "RemoveDialPlanException" ? "Remove selected exception" : "Edit selected exception")
            page.addSubview(control)
        }
    }

    private func buildTestPage(_ page: NSView) {
        heading("Test an outgoing number", in: page, y: 198)
        textField(testField, identifier: "DialPlanTestNumber", label: "Number to test against this dial plan", frame: NSRect(x: 0, y: 161, width: 516, height: 26), in: page)
        testField.placeholderString = "Number or SIP address"
        label("International destination", in: page, x: 0, y: 126, width: 516, secondary: true)
        canonicalLabel.frame = NSRect(x: 0, y: 99, width: 516, height: 24)
        canonicalLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        canonicalLabel.identifier = NSUserInterfaceItemIdentifier("DialPlanCanonicalPreview")
        canonicalLabel.setAccessibilityLabel("Normalised outgoing destination")
        page.addSubview(canonicalLabel)
        heading("Connection and matching rule", in: page, y: 73)
        routeLabel.frame = NSRect(x: 0, y: 43, width: 516, height: 24)
        routeLabel.identifier = NSUserInterfaceItemIdentifier("DialPlanRoutePreview")
        page.addSubview(routeLabel)
        previewMessage.frame = NSRect(x: 0, y: 1, width: 516, height: 37)
        previewMessage.font = .systemFont(ofSize: 11)
        previewMessage.identifier = NSUserInterfaceItemIdentifier("DialPlanPreviewExplanation")
        page.addSubview(previewMessage)
    }

    private var rules: [[String: Any]] { draft["rules"] as? [[String: Any]] ?? [] }

    private func refreshControls() {
        select(countryMenu, value: draft["countryCode"] as? String ?? "+44")
        areaField.stringValue = draft["areaCode"] as? String ?? "01442"
        refreshNumberExample()
        refreshRouteCoverage()
        refreshAccountPresentation(forceControls: true)
        updateDirtyState()
        if !store.configurationError.isEmpty { showError("Saved plan needs repair. Review these fields and Save. \(store.configurationError)") }
    }

    private func refreshAccountPresentation(forceControls: Bool = false) {
        guard isViewLoaded else { return }
        let accounts = accountProvider()
        let accountsChanged = accounts.count != renderedAccounts.count || zip(accounts, renderedAccounts).contains { next, previous in
            next.uuid != previous.uuid || next.name != previous.name || next.enabled != previous.enabled
                || next.availability != previous.availability
        }
        renderedAccounts = accounts
        // Number/draft edits need a fresh preview, but stable accounts should
        // not rebuild eight menus and the exception table on every keystroke.
        if forceControls || accountsChanged {
            refreshAccountMenus()
            rulesTable.reloadData()
            if let target = editorFields["target"] as? NSPopUpButton {
                populate(target, selected: selectedValue(target), defaultTitle: "Choose connection…", allowsBlock: true)
            }
        }
        updatePreview()
    }

    private func refreshAccountMenus() {
        for (key, menu) in selectors {
            let isCategory = categories.contains { $0.0 == key }
            let target = isCategory ? (draft["categoryTargets"] as? [String: String])?[key] ?? "" : draft[key] as? String ?? ""
            populate(menu, selected: target, defaultTitle: key == "emergencyAccountUUID" ? "Not configured" : isCategory ? "Default connection" : "Choose connection…", allowsBlock: isCategory)
        }
    }

    private func populate(_ menu: NSPopUpButton, selected: String, defaultTitle: String?, allowsBlock: Bool) {
        menu.removeAllItems()
        if let defaultTitle { addItem(defaultTitle, value: "", to: menu) }
        var displayedUUIDs = Set<String>()
        for account in renderedAccounts where displayedUUIDs.insert(account.uuid).inserted {
            if renderedAccounts.filter({ $0.uuid == account.uuid }).count > 1 {
                addItem("Ambiguous connection", value: account.uuid, to: menu)
                menu.lastItem?.isEnabled = false
                continue
            }
            let name = account.name.isEmpty ? "Connection" : account.name
            addItem(account.enabled ? name : "\(name) — Disabled", value: account.uuid, to: menu)
            menu.lastItem?.isEnabled = account.enabled
        }
        if allowsBlock { addItem("Block", value: "block", to: menu) }
        if !selected.isEmpty && !menu.itemArray.contains(where: { ($0.representedObject as? String) == selected }) {
            addItem("Missing connection", value: selected, to: menu)
            menu.lastItem?.isEnabled = false
        }
        select(menu, value: selected)
    }

    private func addItem(_ title: String, value: String, to menu: NSPopUpButton) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = value
        menu.menu?.addItem(item)
    }

    private func select(_ menu: NSPopUpButton, value: String) {
        if let item = menu.itemArray.first(where: { ($0.representedObject as? String) == value }) { menu.select(item) }
    }

    private func selectedValue(_ menu: NSPopUpButton) -> String { menu.selectedItem?.representedObject as? String ?? "" }

    private func refreshNumberExample() {
        if (draft["countryCode"] as? String) == "+44" && (draft["areaCode"] as? String) == "01442" {
            numberExampleLabel.stringValue = "07799414799 → +447799414799  ·  242110 → +441442242110"
        } else {
            numberExampleLabel.stringValue = "Numbers are converted to international format before choosing a connection."
        }
        numberExampleLabel.toolTip = numberExampleLabel.stringValue
    }

    private func refreshRouteCoverage() {
        let country = draft["countryCode"] as? String ?? "+44"
        let coverage = country == "+44"
            ? "Mobile/Landline/Premium: UK ranges. Longest active prefix wins."
            : "UK-only Mobile/Landline/Premium; \(country) domestic telephone numbers use Other."
        let help = countryCoverageDescription(country)
            + " Numbers outside \(country) are International. Short/service codes and protected exact emergencies retain their separate rules."
            + " The longest matching active prefix wins. Offline connections never silently fall back."
        routeCoverageLabel.stringValue = coverage
        routeCoverageLabel.toolTip = help
        routeCoverageLabel.setAccessibilityValue(coverage)
        routeCoverageLabel.setAccessibilityHelp(help)
        for (key, menu) in selectors where categories.contains(where: { $0.0 == key }) {
            menu.toolTip = help
            menu.setAccessibilityHelp(help)
            menu.cell?.setAccessibilityHelp(help)
        }
    }

    private func countryCoverageDescription(_ country: String) -> String {
        country == "+44"
            ? "Domestic UK telephone ranges include Mobile, Landline and Premium classification."
            : "Domestic telephone numbers in \(country) use Other. Mobile/Landline/Premium range classification is UK-only."
    }

    private func installSelector(key: String, label: String, frame: NSRect, in page: NSView) {
        let menu = NSPopUpButton(frame: frame, pullsDown: false)
        menu.identifier = NSUserInterfaceItemIdentifier("DialPlanTarget.\(key)")
        menu.setAccessibilityLabel(label)
        menu.cell?.setAccessibilityLabel(label)
        menu.target = self
        menu.action = #selector(targetChanged(_:))
        selectors[key] = menu
        page.addSubview(menu)
    }

    @objc private func targetChanged(_ sender: NSPopUpButton) {
        guard let key = selectors.first(where: { $0.value === sender })?.key else { return }
        if categories.contains(where: { $0.0 == key }) {
            var targets = draft["categoryTargets"] as? [String: String] ?? [:]
            targets[key] = selectedValue(sender)
            draft["categoryTargets"] = targets
        } else { draft[key] = selectedValue(sender) }
        didChangeDraft()
    }

    @objc private func countryChanged(_ sender: NSPopUpButton) {
        draft["countryCode"] = selectedValue(sender)
        refreshNumberExample()
        refreshRouteCoverage()
        didChangeDraft()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === areaField {
            draft["areaCode"] = field.stringValue
            refreshNumberExample()
            didChangeDraft()
        } else if field === testField { refreshAccountPresentation() }
        else if field === editorFields["comment"] {
            let count = field.stringValue.count
            editorFields["commentCount"]?.setAccessibilityValue("\(count) of 20 characters")
            (editorFields["commentCount"] as? NSTextField)?.stringValue = "\(count)/20"
        }
    }

    private func didChangeDraft() {
        statusLabel.stringValue = "Unsaved changes"
        statusLabel.textColor = .secondaryLabelColor
        updateDirtyState()
        refreshAccountPresentation()
    }

    private func updateDirtyState() { saveButton.isEnabled = hasUnsavedChanges || !store.configurationError.isEmpty }

    @objc private func changePage(_ sender: NSSegmentedControl) {
        for (index, page) in pages.enumerated() { page.isHidden = index != sender.selectedSegment }
        if sender.selectedSegment == 3 { refreshAccountPresentation() }
        view.window?.recalculateKeyViewLoop()
    }

    @objc private func save(_ sender: Any?) { _ = saveDraft() }

    @discardableResult
    private func saveDraft() -> Bool {
        view.window?.makeFirstResponder(nil)
        isSavingDraft = true
        defer { isSavingDraft = false }
        do {
            try store.updateConfiguration(draft)
            draft = store.configuration
            saved = draft
            refreshControls()
            statusLabel.stringValue = "Dial plan saved"
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.toolTip = nil
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func reloadSavedConfiguration() {
        draft = store.configuration
        saved = draft
        if isViewLoaded {
            refreshControls()
            if store.configurationError.isEmpty { statusLabel.stringValue = "" }
        }
    }

    private func updatePreview() {
        guard isViewLoaded else { return }
        guard !testField.stringValue.isEmpty else {
            canonicalLabel.stringValue = "Enter a number to preview"
            canonicalLabel.toolTip = nil
            routeLabel.stringValue = ""
            routeLabel.toolTip = nil
            setPreviewExplanation("This preview uses the current fields, including unsaved changes.", color: .secondaryLabelColor)
            return
        }
        do {
            let route = try store.previewDestination(testField.stringValue, configuration: draft, accounts: renderedAccounts)
            let presentation = DialPlanRoutePresentation(route: route, accounts: renderedAccounts)
            canonicalLabel.stringValue = route.destination.canonical
            routeLabel.stringValue = presentation.routeText
            routeLabel.textColor = route.blocked || !route.canDial ? .systemRed : .controlTextColor
            setPreviewExplanation(presentation.explanation, color: route.canDial ? .secondaryLabelColor : .systemRed)
            routeLabel.toolTip = presentation.detailText
            canonicalLabel.toolTip = route.destination.canonical
        } catch {
            canonicalLabel.stringValue = "Check the dial-plan fields"
            canonicalLabel.toolTip = nil
            routeLabel.stringValue = ""
            routeLabel.toolTip = nil
            setPreviewExplanation(error.localizedDescription, color: .systemRed)
        }
    }

    private func setPreviewExplanation(_ message: String, color: NSColor) {
        previewMessage.stringValue = message
        previewMessage.textColor = color
        previewMessage.toolTip = message
        previewMessage.setAccessibilityValue(message)
    }

    @objc(confirmLeavingWithCompletion:)
    func confirmLeaving(completion: @escaping (Bool) -> Void) {
        guard hasUnsavedChanges else { completion(true); return }
        guard let window = view.window else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = "Save changes to the dial plan?"
        alert.informativeText = "The dialler continues to use the saved rules until you save these changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { completion(false); return }
            if response == .alertFirstButtonReturn { completion(self.saveDraft()) }
            else if response == .alertSecondButtonReturn { self.reloadSavedConfiguration(); completion(true) }
            else { completion(false) }
        }
    }

    @objc private func showPrefixes(_ sender: Any?) {
        guard prefixesSheet == nil, let parent = view.window, parent.attachedSheet == nil else { return }
        let country = store.configuration["countryCode"] as? String ?? "+44"
        let needsRepair = !store.configurationError.isEmpty
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 484, height: 244), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = needsRepair ? "Guided prefixes for displayed \(country)" : "Guided prefixes for \(country)"
        guard let content = panel.contentView else { return }
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 63, width: 452, height: 165))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 432, height: 165))
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: 12)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.minSize = NSSize(width: 0, height: 165)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.identifier = NSUserInterfaceItemIdentifier("DialPlanPrefixDetails")
        text.setAccessibilityLabel(needsRepair ? "Guided route prefixes for the displayed repair country" : "Actual guided route prefixes for the saved country")
        text.setAccessibilityHelp(needsRepair ? "The saved plan needs repair. These prefixes describe the displayed country, not a valid saved plan." : "This list uses the saved country. Save country changes to update it.")
        let countryStatus = needsRepair
            ? "Displayed country: \(country)\nSaved plan needs repair. Routing is blocked until you repair and save it.\n\(store.configurationError)"
            : "Saved country: \(country)"
        let information = "\(DialPlanStore.metadataVersion)\n\(countryStatus)\n\(countryCoverageDescription(country))"
            + " Short/service codes and protected exact emergencies retain their separate rules.\n"
            + "Supported home-country profiles: \(DialPlanStore.supportedCountryCodes.joined(separator: ", ")).\n"
            + "Offline numbering information; ranges do not establish provider prices, allocation or reachability."
        let prefixes = categories.map { key, title in
            "\(title)\n\(store.categoryPrefixes(key).joined(separator: ", "))"
        }.joined(separator: "\n\n")
        text.string = information + "\n\n" + prefixes
        text.sizeToFit()
        scroll.documentView = text
        content.addSubview(scroll)
        label(needsRepair ? "Repair and save the plan to update this list. Longest active prefix wins." : "Save country changes to update this list. Longest active prefix wins.", in: content, x: 16, y: 38, width: 452, secondary: true)
        let done = button("Done", action: #selector(closePrefixes(_:)), identifier: "CloseDialPlanPrefixes")
        done.frame = NSRect(x: 386, y: 5, width: 82, height: 26)
        done.keyEquivalent = "\r"
        content.addSubview(done)
        prefixesSheet = panel
        parent.beginSheet(panel)
    }

    @objc private func closePrefixes(_ sender: Any?) {
        if let panel = prefixesSheet { panel.sheetParent?.endSheet(panel); panel.orderOut(nil) }
        prefixesSheet = nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rules.count, let key = tableColumn?.identifier.rawValue else { return nil }
        let rule = rules[row]
        if key == "enabled" {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleException(_:)))
            checkbox.tag = row
            checkbox.state = (rule["enabled"] as? Bool ?? true) ? .on : .off
            checkbox.setAccessibilityLabel("Enable exception \(rule["prefix"] as? String ?? "")")
            return checkbox
        }
        let target = rule["target"] as? String ?? ""
        let matches = renderedAccounts.filter { $0.uuid == target }
        let name = matches.count == 1 ? matches[0].name : matches.isEmpty ? "Missing connection" : "Ambiguous connection"
        let text = key == "target" ? target == "block" ? "Block" : name : rule[key] as? String ?? ""
        let value = NSTextField(labelWithString: text)
        value.lineBreakMode = .byTruncatingTail
        value.toolTip = text
        return value
    }

    @objc private func toggleException(_ sender: NSButton) {
        var values = rules
        guard values.indices.contains(sender.tag) else { return }
        values[sender.tag]["enabled"] = sender.state == .on
        draft["rules"] = values
        didChangeDraft()
    }

    @objc private func addException(_ sender: Any?) { presentException(nil) }
    @objc private func editException(_ sender: Any?) {
        guard rules.indices.contains(rulesTable.selectedRow) else { return }
        presentException(rules[rulesTable.selectedRow])
    }
    @objc private func removeException(_ sender: Any?) {
        var values = rules
        guard values.indices.contains(rulesTable.selectedRow) else { return }
        values.remove(at: rulesTable.selectedRow)
        draft["rules"] = values
        rulesTable.reloadData()
        didChangeDraft()
    }

    private func presentException(_ rule: [String: Any]?) {
        guard exceptionEditor == nil, let parent = view.window else { return }
        refreshAccountPresentation()
        editingRuleID = rule?["id"] as? String
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 388, height: 226), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = rule == nil ? "Add exception" : "Edit exception"
        guard let content = panel.contentView else { return }
        let enabled = NSButton(checkboxWithTitle: "Active", target: nil, action: nil)
        enabled.frame = NSRect(x: 16, y: 191, width: 150, height: 22)
        enabled.state = (rule?["enabled"] as? Bool ?? true) ? .on : .off
        enabled.identifier = NSUserInterfaceItemIdentifier("ExceptionEnabled")
        content.addSubview(enabled)
        label("Prefix", in: content, x: 16, y: 160, width: 82)
        let prefix = NSTextField(string: rule?["prefix"] as? String ?? "")
        textField(prefix, identifier: "ExceptionPrefix", label: "Exception prefix", frame: NSRect(x: 104, y: 157, width: 268, height: 23), in: content)
        prefix.placeholderString = "+447799, 07799 or a service prefix"
        label("Connection", in: content, x: 16, y: 127, width: 82)
        let target = NSPopUpButton(frame: NSRect(x: 104, y: 120, width: 268, height: 26), pullsDown: false)
        target.identifier = NSUserInterfaceItemIdentifier("ExceptionTarget")
        target.setAccessibilityLabel("Exception connection or Block")
        target.cell?.setAccessibilityLabel("Exception connection or Block")
        populate(target, selected: rule?["target"] as? String ?? "", defaultTitle: "Choose connection…", allowsBlock: true)
        content.addSubview(target)
        label("Comment", in: content, x: 16, y: 91, width: 82)
        let comment = NSTextField(string: rule?["comment"] as? String ?? "")
        textField(comment, identifier: "ExceptionComment", label: "Exception comment, up to 20 characters", frame: NSRect(x: 104, y: 88, width: 214, height: 23), in: content)
        let count = NSTextField(labelWithString: "\(comment.stringValue.count)/20")
        count.frame = NSRect(x: 324, y: 91, width: 48, height: 18)
        count.font = .systemFont(ofSize: 11)
        content.addSubview(count)
        let error = NSTextField(wrappingLabelWithString: "")
        error.frame = NSRect(x: 16, y: 39, width: 356, height: 39)
        error.font = .systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.identifier = NSUserInterfaceItemIdentifier("ExceptionValidationMessage")
        content.addSubview(error)
        let cancel = button("Cancel", action: #selector(cancelException(_:)), identifier: "CancelException")
        cancel.frame = NSRect(x: 196, y: 5, width: 82, height: 26)
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(cancel)
        let accept = button("Done", action: #selector(acceptException(_:)), identifier: "AcceptException")
        accept.frame = NSRect(x: 290, y: 5, width: 82, height: 26)
        accept.keyEquivalent = "\r"
        content.addSubview(accept)
        editorFields = ["enabled": enabled, "prefix": prefix, "target": target, "comment": comment, "commentCount": count, "error": error]
        exceptionEditor = panel
        parent.beginSheet(panel)
        panel.makeFirstResponder(prefix)
    }

    @objc private func acceptException(_ sender: Any?) {
        guard let panel = exceptionEditor, let prefix = editorFields["prefix"] as? NSTextField,
              let target = editorFields["target"] as? NSPopUpButton,
              let comment = editorFields["comment"] as? NSTextField,
              let enabled = editorFields["enabled"] as? NSButton else { return }
        panel.makeFirstResponder(nil)
        var values = rules
        let id = editingRuleID ?? UUID().uuidString
        let rule: [String: Any] = ["id": id, "prefix": prefix.stringValue,
                                  "enabled": enabled.state == .on, "target": selectedValue(target),
                                  "comment": comment.stringValue]
        if let index = values.firstIndex(where: { ($0["id"] as? String) == id }) { values[index] = rule }
        else { values.append(rule) }
        var candidate = draft
        candidate["rules"] = values
        do {
            _ = try store.previewDestination("07799414799", configuration: candidate, accounts: renderedAccounts)
            draft = candidate
            finishException()
            rulesTable.reloadData()
            didChangeDraft()
        } catch {
            (editorFields["error"] as? NSTextField)?.stringValue = error.localizedDescription
        }
    }

    @objc private func cancelException(_ sender: Any?) { finishException() }

    private func finishException() {
        if let panel = exceptionEditor { panel.sheetParent?.endSheet(panel); panel.orderOut(nil) }
        exceptionEditor = nil
        editorFields = [:]
        editingRuleID = nil
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.toolTip = message
        statusLabel.textColor = .systemRed
        statusLabel.setAccessibilityValue(message)
    }

    private func heading(_ title: String, in parent: NSView, y: CGFloat) {
        let value = NSTextField(labelWithString: title)
        value.frame = NSRect(x: 0, y: y, width: 370, height: 18)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        value.identifier = NSUserInterfaceItemIdentifier("SettingsSectionHeading")
        value.setAccessibilityLabel(title)
        if #available(macOS 26.0, *) { value.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading")) }
        parent.addSubview(value)
    }

    private func label(_ title: String, in parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat, secondary: Bool = false) {
        let value = NSTextField(labelWithString: title)
        value.frame = NSRect(x: x, y: y, width: width, height: 18)
        value.font = .systemFont(ofSize: secondary ? 11 : 12)
        value.textColor = secondary ? .secondaryLabelColor : .labelColor
        value.lineBreakMode = .byTruncatingTail
        value.toolTip = title
        parent.addSubview(value)
    }

    private func textField(_ field: NSTextField, identifier: String, label: String, frame: NSRect, in parent: NSView) {
        field.frame = frame
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.delegate = self
        field.setAccessibilityLabel(label)
        field.cell?.setAccessibilityLabel(label)
        parent.addSubview(field)
    }

    private func button(_ title: String, action: Selector, identifier: String) -> NSButton {
        let value = NSButton(title: title, target: self, action: action)
        value.bezelStyle = .rounded
        value.identifier = NSUserInterfaceItemIdentifier(identifier)
        value.setAccessibilityLabel(title)
        value.cell?.setAccessibilityLabel(title)
        return value
    }
}
