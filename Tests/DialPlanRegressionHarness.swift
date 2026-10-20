import Foundation

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@main
@MainActor
struct DialPlanRegressionHarness {
    static var cases = 0
    static var failures: [String] = []
    static let local = "9E554680-C872-4A22-AE03-990ABAE51A9D"
    static let aa = "B9064E53-3B9B-40ED-9853-C9AD03E8939E"

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        cases += 1
        if !condition() { failures.append(name) }
    }

    static func rule(_ prefix: String, _ target: String, enabled: Bool = true, comment: String = "") -> [String: Any] {
        ["id": UUID().uuidString, "prefix": prefix, "enabled": enabled, "target": target, "comment": comment]
    }

    static func configuration(_ store: DialPlanStore, targets: [String: String] = [:],
                              rules: [[String: Any]] = []) -> [String: Any] {
        var value = store.configuration
        value["defaultAccountUUID"] = aa
        value["emergencyAccountUUID"] = aa
        value["categoryTargets"] = targets
        value["rules"] = rules
        return value
    }

    static var accounts: [DialPlanAccount] {
        [DialPlanAccount(uuid: local, name: "Localphone", enabled: true, availability: "online"),
         DialPlanAccount(uuid: aa, name: "AA", enabled: true, availability: "online")]
    }

    static func rejected(_ name: String, store: DialPlanStore, _ value: [String: Any]) {
        let before = store.defaults.data(forKey: DialPlanStore.settingsKey)
        do {
            try store.updateConfiguration(value)
            check(name, false)
        } catch { check(name, store.defaults.data(forKey: DialPlanStore.settingsKey) == before) }
    }

    static func checkRoutePresentation(store: DialPlanStore) throws {
        let settings = configuration(store, targets: ["mobile": local])
        for (enabled, availability, status) in [
            (true, "online", "Ready"), (true, "unavailable", "Ready"),
            (true, "registering", "Waiting"), (true, "needsRegistration", "Waiting"),
            (true, "offline", "Offline"), (true, "failed", "Unavailable"),
            (true, "unknown", "Unavailable"), (false, "online", "Disabled"),
            (false, "needsRegistration", "Disabled")
        ] {
            let snapshot = [DialPlanAccount(uuid: local, name: "Localphone", enabled: enabled, availability: availability), accounts[1]]
            let route = try store.previewDestination("07799414799", configuration: settings, accounts: snapshot)
            let display = DialPlanRoutePresentation(route: route, accounts: snapshot)
            check("presentation \(enabled)/\(availability) keeps compact status", display.compactStatus == "\(status) · Localphone")
            check("presentation \(enabled)/\(availability) keeps matching provider and no fallback", display.providerName == "Localphone" && display.ruleDescription == "Prefix +4477" && route.accountUUID == local)
            check("presentation \(enabled)/\(availability) keeps destination and explanation", display.detailText == "+447799414799\n\(route.message)" && display.explanation == route.message)
        }
        let missing = try store.previewDestination("07799414799", configuration: settings, accounts: [accounts[1]])
        let removed = DialPlanRoutePresentation(route: missing, accounts: [accounts[1]])
        check("presentation preserves removed connection status without fallback", removed.compactStatus == "Connection removed" && removed.providerName == "No connection" && missing.accountUUID == local)
        let duplicateAccounts = accounts + [DialPlanAccount(uuid: local, name: "Different name", enabled: true, availability: "online")]
        let ambiguous = try store.previewDestination("07799414799", configuration: settings, accounts: duplicateAccounts)
        let ambiguousDisplay = DialPlanRoutePresentation(route: ambiguous, accounts: duplicateAccounts)
        check("presentation never picks arbitrary duplicate UUID provider", ambiguousDisplay.compactStatus == "Unavailable · Ambiguous connection" && ambiguousDisplay.providerName == "Ambiguous connection" && ambiguousDisplay.explanation == ambiguous.message && !ambiguous.canDial)

        let blocked = try store.previewDestination("07799414799", configuration: configuration(store, targets: ["mobile": "block"]), accounts: accounts)
        let blockedDisplay = DialPlanRoutePresentation(route: blocked, accounts: accounts)
        check("presentation preserves Block and matched prefix", blockedDisplay.compactStatus == "Blocked by dial plan" && blockedDisplay.routeText == "Blocked · Prefix +4477" && blockedDisplay.explanation == blocked.message)
        let emergency = try store.previewDestination("999", configuration: settings, accounts: accounts)
        let emergencyDisplay = DialPlanRoutePresentation(route: emergency, accounts: accounts)
        check("presentation preserves protected emergency provider", emergencyDisplay.compactStatus == "Ready · AA" && emergencyDisplay.routeText == "AA · Emergency" && emergencyDisplay.detailText == "999\nUse AA.")
        for input in ["123R45P67", "*21*07799414799#", "101", "sip:alice@example.net"] {
            let route = try store.previewDestination(input, configuration: settings, accounts: accounts)
            let display = DialPlanRoutePresentation(route: route, accounts: accounts)
            check("presentation preserves literal service/SIP destination \(input)", display.detailText.hasPrefix(input + "\n") && display.providerName == "AA")
            let explanation = [route.message, route.destination.message].filter { !$0.isEmpty }.joined(separator: " ")
            check("presentation retains route plus numbering guidance \(input)", display.explanation == explanation)
        }
        let invalid = try store.previewDestination("07799x414799", configuration: settings, accounts: accounts)
        let invalidDisplay = DialPlanRoutePresentation(route: invalid, accounts: accounts)
        check("presentation deduplicates invalid destination explanation", invalidDisplay.compactStatus == "Check number" && invalidDisplay.explanation == invalid.message && invalid.message == invalid.destination.message)
        var unconfigured = settings
        unconfigured["defaultAccountUUID"] = ""
        unconfigured["emergencyAccountUUID"] = ""
        for input in ["999", "242110"] {
            let route = try store.previewDestination(input, configuration: unconfigured, accounts: accounts)
            let display = DialPlanRoutePresentation(route: route, accounts: accounts)
            check("presentation retains unconfigured route message \(input)", display.compactStatus == route.message && display.explanation == route.message && route.accountUUID == nil && !route.canDial)
        }
    }

    static func main() throws {
        let domain = "test.jps.dialplan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = DialPlanStore(defaults: defaults)
        check("new store does not write real or synthetic preferences on init", defaults.object(forKey: DialPlanStore.settingsKey) == nil)
        check("defaults use required country and area", store.configuration["countryCode"] as? String == "+44" && store.configuration["areaCode"] as? String == "01442")

        let equivalentMobile = ["07799414799", "+447799414799", "00447799414799", "07799 414 799", "(+44) 7799-414799", "tel:%2B447799414799", "tel:07799%20414799", "07799\u{00a0}414799"]
        for input in equivalentMobile {
            let number = store.normaliseDestination(input)
            check("mobile canonical equivalence: \(input)", number.valid && number.canonicalNumber == "+447799414799" && number.category == "mobile")
        }
        for input in ["tel://07799414799", "TEL://%2B447799414799"] {
            check("legacy telephone URL alias canonicalises before routing: \(input)", store.normaliseDestination(input).canonicalNumber == "+447799414799")
        }
        for input in ["sip://alice@example.net:5070;transport=tcp", "SIP://alice@example.net:5070;transport=tcp"] {
            let n = store.normaliseDestination(input)
            check("legacy SIP URL alias cannot dial slash-prefixed username: \(input)", n.valid && n.destination == "sip:alice@example.net:5070;transport=tcp")
        }
        check("legacy SIP alias retains strict unsupported-parameter rejection", !store.normaliseDestination("sip://alice@example.net?subject=call").valid)
        check("legacy telephone alias retains strict unsupported-parameter rejection", !store.normaliseDestination("tel://07799414799;ext=1").valid)
        for input in ["242110", "01442242110", "+441442242110", "00441442242110", "01442 242110"] {
            check("landline canonical equivalence: \(input)", store.normaliseDestination(input).canonicalNumber == "+441442242110")
        }
        for input in ["", "07799x414799", "07799/414799", "07799,414799", "+44+7799414799", "+0447799414799", "+999123456789", "+44779941479999999", "07799\n414799", "tel:%ZZ", "tel:07799414799;ext=3", "tel:sales", "+330123456789", "sips:alice@example.net:5061", "mailto:alice@example.net", "sip:alice@@example.net"] {
            check("invalid input cannot become a different dialled number: \(input)", !store.normaliseDestination(input).valid)
        }
        for input in ["999", "112", "tel:999", " 112 "] {
            let n = store.normaliseDestination(input)
            check("exact emergency preserved: \(input)", n.kind == "emergency" && n.canonicalNumber == nil)
        }
        check("longer number is not an emergency prefix", store.normaliseDestination("999123").kind == "telephone")
        for input in ["101", "111", "1234", "116123", "118118", "*21*07799414799#", "1800107799414799", "123R45P67"] {
            let n = store.normaliseDestination(input)
            check("short/service destination is never prefixed: \(input)", n.valid && n.destination == input && n.canonicalNumber == nil && n.category == "service")
        }
        for input in ["sip:07799414799@example.net:5070;transport=tcp", "sip:alice@example.net:5061;transport=tls", "alice@example.net", "sales-support"] {
            let n = store.normaliseDestination(input)
            check("SIP identity preserved exactly: \(input)", n.valid && n.kind == "sip" && n.destination == input && n.canonicalNumber == nil)
        }
        check("incomplete SIP URI rejected", !store.normaliseDestination("sip:alice@").valid)
        check("SIP whitespace rejected", !store.normaliseDestination("sip:alice@bad host").valid)
        check("malformed bracketed IPv6 is not rewritten as a host/port", !store.normaliseDestination("sip:alice@[bad:def]:5070").valid)
        for input in ["sip:alice@example.net;user=phone", "sip:alice@example.net;transport=ws", "sip:alice@example.net;transport=tcp;transport=tls", "sip:alice@example.net;transport=tcp;user=phone", "sip:alice@example.net;", "sip:alice@example.net?subject=call", "sip:alice@example.net:abc", "sip:alice@example.net:0", "sip:alice@example.net:65536", "sip:alice@[2001:db8::1]:-1", "sip:alice@2001:db8::1", "sip:alice@bad..host", "sip:alice@:5070", "sip:alice@[2001:db8::1"] {
            check("unsupported/malformed SIP cannot silently change target: \(input)", !store.normaliseDestination(input).valid)
        }
        for input in ["sip:alice@example.net;transport=udp", "alice@example.net:5070;transport=tcp", "sip:alice@example.net:5061;Transport=TLS", "sip:alice@[2001:db8::1]:5070;transport=tcp", "sip:alice@192.0.2.1:1", "sip:alice@localhost:65535"] {
            let n = store.normaliseDestination(input)
            check("supported SIP host/port/transport retained: \(input)", n.valid && n.destination == input)
        }

        let classifications: [(String, String)] = [
            ("07100123456", "mobile"), ("07500123456", "mobile"), ("07900123456", "mobile"),
            ("07000123456", "other"), ("07600123456", "other"), ("07624123456", "mobile"),
            ("02079460000", "landline"), ("03001234567", "service"), ("03301234567", "service"),
            ("08001234567", "service"), ("08451234567", "service"), ("08731234567", "service"),
            ("05512345678", "other"), ("05612345678", "other"), ("09012345678", "premium"),
            ("09112345678", "premium"), ("09812345678", "premium"), ("+33123456789", "international")
        ]
        for (number, category) in classifications {
            check("Ofcom classification \(number)", store.normaliseDestination(number).category == category)
        }
        check("prefix display includes exact IOM mobile exception", store.categoryPrefixes("mobile").contains("+447624"))
        check("short national freephone retains complete number", store.normaliseDestination("08001111").canonicalNumber == "+448001111")
        check("short full international freephone remains valid", store.normaliseDestination("+448001111").category == "service")
        check("incomplete nine-digit NSN mobile is rejected", !store.normaliseDestination("0779941479").valid)
        check("incomplete full international mobile rejected under any default", !store.normaliseDestination("+44779941479").valid)

        try store.updateConfiguration(configuration(store, targets: ["mobile": local, "premium": "block"], rules: [rule("+44", "block")]))
        var result = store.resolveDestination("07799414799", accounts: accounts)
        check("generated mobile prefix beats broad country Block", result.accountUUID == local && result.canDial && result.matchedPrefix == "+4477")
        result = store.resolveDestination("09012345678", accounts: accounts)
        check("generated Premium Block beats broad country rule", result.blocked && result.matchedPrefix == "+4490")
        try store.updateConfiguration(configuration(store, targets: ["mobile": local], rules: [rule("+447", "block")]))
        check("generated mobile prefix beats broad 07 Block", store.resolveDestination("07799414799", accounts: accounts).accountUUID == local)
        try store.updateConfiguration(configuration(store, targets: ["mobile": local], rules: [rule("+447799", aa), rule("+447799414", "block", enabled: false)]))
        result = store.resolveDestination("07799414799", accounts: accounts)
        check("precise exception beats category, disabled narrower rule ignored", result.accountUUID == aa && result.matchedPrefix == "+447799")
        try store.updateConfiguration(configuration(store, targets: ["mobile": local], rules: [rule("+4477", aa)]))
        check("equal-prefix custom exception overrides generated route", store.resolveDestination("07799414799", accounts: accounts).accountUUID == aa)
        try store.updateConfiguration(configuration(store, targets: ["mobile": ""], rules: [rule("+44", "block")]))
        check("category Default contributes no generated competing rule", store.resolveDestination("07799414799", accounts: accounts).blocked)
        try store.updateConfiguration(configuration(store, targets: ["international": "block"], rules: [rule("+33", local)]))
        check("foreign precise exception overrides International fallback", store.resolveDestination("+33123456789", accounts: accounts).accountUUID == local)
        check("other foreign number uses explicit International Block", store.resolveDestination("+12125551234", accounts: accounts).blocked)
        try store.updateConfiguration(configuration(store, targets: ["other": "block"]))
        check("07624 exception prevents broad pager Other category", store.resolveDestination("07624123456", accounts: accounts).accountUUID == aa)
        check("070 personal number uses Other rule", store.resolveDestination("07000123456", accounts: accounts).blocked)

        try store.updateConfiguration(configuration(store, targets: ["service": "block"], rules: [rule("999", "block"), rule("112", local)]))
        check("emergency exact overrides Block/custom and uses explicit AA", store.resolveDestination("999", accounts: accounts).accountUUID == aa)
        check("emergency exact cannot be repinned by custom112", store.resolveDestination("112", accounts: accounts).accountUUID == aa)
        check("112 prefix does not turn longer shortcode into emergency", store.resolveDestination("1123", accounts: accounts).accountUUID == local)
        var noEmergency = configuration(store)
        noEmergency["emergencyAccountUUID"] = ""
        try store.updateConfiguration(noEmergency)
        check("unconfigured emergency does not fall back to default", !store.resolveDestination("999", accounts: accounts).canDial && store.resolveDestination("999", accounts: accounts).accountUUID == nil)

        try store.updateConfiguration(configuration(store, targets: ["mobile": local]))
        for state in ["online", "unavailable", "registering", "needsRegistration", "offline", "failed", "unknown"] {
            let offered = [DialPlanAccount(uuid: local, name: "Localphone", enabled: true, availability: state), accounts[1]]
            let route = store.resolveDestination("07799414799", accounts: offered)
            check("selected account state \(state) never falls back", route.accountUUID == local && route.canDial == ["online", "unavailable", "registering", "needsRegistration"].contains(state))
            check("registration queue only for allowed pending states \(state)", route.requiresRegistration == ["registering", "needsRegistration"].contains(state))
        }
        check("deleted selected account fails without fallback", !store.resolveDestination("07799414799", accounts: [accounts[1]]).canDial && store.resolveDestination("07799414799", accounts: [accounts[1]]).accountUUID == local)
        check("disabled selected account fails without fallback", !store.resolveDestination("07799414799", accounts: [DialPlanAccount(uuid: local, name: "Localphone", enabled: false, availability: "online"), accounts[1]]).canDial)
        check("duplicate account identity cannot route", !store.resolveDestination("07799414799", accounts: accounts + [accounts[0]]).canDial)

        let incomingCanonical = store.normaliseDestination("07799414799").canonicalNumber!
        let pendingLocalRequest = store.resolveDestination(incomingCanonical, accounts: accounts)
        check("AA incoming canonical number callbacks on current Localphone route", store.resolveDestination(incomingCanonical, accounts: accounts).accountUUID == local)
        try store.updateConfiguration(configuration(store, targets: ["mobile": aa]))
        check("changed plan is reevaluated on callback", store.resolveDestination(incomingCanonical, accounts: accounts).accountUUID == aa)
        check("already admitted request retains immutable account and canonical destination", pendingLocalRequest.accountUUID == local && pendingLocalRequest.destination.canonicalNumber == incomingCanonical)
        var changedArea = configuration(store)
        changedArea["areaCode"] = "020"
        try store.updateConfiguration(changedArea)
        check("stored international destination is stable after default area change", store.normaliseDestination("+441442242110").canonicalNumber == "+441442242110")
        check("new local input uses changed area", store.normaliseDestination("79460000").canonicalNumber == "+442079460000")
        changedArea["areaCode"] = ""
        try store.updateConfiguration(changedArea)
        check("local number without area fails without guessing", !store.normaliseDestination("242110").valid)
        check("international number without area remains valid", store.normaliseDestination(incomingCanonical).valid)

        let regionalCases: [(String, String, String, String)] = [
            ("+1", "212", "5551234", "+12125551234"), ("+1", "212", "12125551234", "+12125551234"),
            ("+1", "212", "2125551234", "+12125551234"), ("+1", "212", "011447799414799", "+447799414799"),
            ("+33", "01", "0123456789", "+33123456789"), ("+33", "01", "23456789", "+33123456789"),
            ("+49", "030", "03012345678", "+493012345678"), ("+49", "030", "12345678", "+493012345678"),
            ("+39", "02", "0212345678", "+390212345678"), ("+39", "02", "12345678", "+390212345678")
        ]
        for (country, area, input, expected) in regionalCases {
            var value = configuration(store)
            value["countryCode"] = country; value["areaCode"] = area
            try store.updateConfiguration(value)
            check("metadata-specific trunk/area handling \(country) \(input)", store.normaliseDestination(input).canonicalNumber == expected)
        }
        check("Italy significant0 retained for full international number", store.normaliseDestination("+390212345678").canonicalNumber == "+390212345678")
        var uk = configuration(store)
        uk["countryCode"] = "+44"; uk["areaCode"] = "01442"
        try store.updateConfiguration(uk)

        rejected("equivalent domestic/international exception duplicate rejected atomically", store: store, configuration(store, rules: [rule("07", local), rule("+447", aa)]))
        rejected("inactive duplicates are still rejected", store: store, configuration(store, rules: [rule("00447", local), rule("+447", aa, enabled: false)]))
        rejected("oversize exception prefix rejected", store: store, configuration(store, rules: [rule("+447799414799123456", aa)]))
        rejected("wildcard characters rejected", store: store, configuration(store, rules: [rule("+447.*", aa)]))
        rejected("comments limited to20 characters", store: store, configuration(store, rules: [rule("+447", aa, comment: String(repeating: "a", count: 21))]))
        rejected("empty exception target rejected", store: store, configuration(store, rules: [rule("+447", "")]))
        var bad = configuration(store); bad["emergencyAccountUUID"] = "block"
        rejected("emergency cannot be blocked in its route selector", store: store, bad)
        bad = configuration(store); bad["schemaVersion"] = 2
        rejected("future schema rejected without overwrite", store: store, bad)
        bad = configuration(store); bad["schemaVersion"] = "2"
        rejected("mistyped future schema rejected without overwrite", store: store, bad)
        bad = configuration(store); bad["countryCode"] = "+81"
        rejected("unsupported domestic region rejected", store: store, bad)
        bad = configuration(store); bad["areaCode"] = "07799"
        rejected("mobile prefix cannot become default geographic area", store: store, bad)

        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name(DialPlanStore.changeNotificationName), object: store, queue: nil) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let beforePreview = defaults.data(forKey: DialPlanStore.settingsKey)
        let draft = configuration(store, targets: ["mobile": local])
        let preview = try store.previewDestination("07799414799", configuration: draft, accounts: accounts)
        check("draft preview routes without writing or notifying", preview.accountUUID == local && defaults.data(forKey: DialPlanStore.settingsKey) == beforePreview && counter.count == 0)
        try store.updateConfiguration(draft)
        check("successful update posts one committed-change notification", counter.count == 1)
        let reload = DialPlanStore(defaults: defaults)
        check("versioned saved plan survives store recreation", reload.resolveDestination("07799414799", accounts: accounts).accountUUID == local && reload.configurationError.isEmpty)
        rejected("failed save never posts change notification", store: store, bad)
        check("invalid config notification unchanged", counter.count == 1)

        defaults.set(Data("corrupt".utf8), forKey: DialPlanStore.settingsKey)
        let corrupt = DialPlanStore(defaults: defaults)
        check("damaged persisted plan blocks dialling instead of silently defaulting", !corrupt.configurationError.isEmpty && !corrupt.resolveDestination("07799414799", accounts: accounts).canDial)
        check("damaged plan bytes retained for repair", defaults.data(forKey: DialPlanStore.settingsKey) == Data("corrupt".utf8))
        let repairRoute = corrupt.resolveDestination("07799414799", accounts: accounts)
        let repairDisplay = DialPlanRoutePresentation(route: repairRoute, accounts: accounts)
        check("presentation retains malformed configuration repair message", repairDisplay.compactStatus == repairRoute.message && repairDisplay.explanation == repairRoute.message && !repairRoute.canDial)
        try corrupt.updateConfiguration(draft)
        check("explicit validated save repairs corrupted configuration", corrupt.configurationError.isEmpty && corrupt.resolveDestination("07799414799", accounts: accounts).canDial)
        defaults.removeObject(forKey: DialPlanStore.settingsKey)
        let migration = DialPlanStore(defaults: defaults)
        migration.bootstrapDefaultAccountUUID(local)
        migration.bootstrapDefaultAccountUUID(aa)
        check("migration pins former default once, never follows reorder", migration.configuration["defaultAccountUUID"] as? String == local)
        check("migration never silently configures emergency account", migration.configuration["emergencyAccountUUID"] as? String == "")
        try checkRoutePresentation(store: store)

        let json: [String: Any] = ["suite": "DialPlanRegressionHarness", "cases": cases,
                                   "failures": failures.count, "failedCases": failures,
                                   "metadataVersion": DialPlanStore.metadataVersion,
                                   "boundary": "production Foundation core with synthetic account IDs and isolated preferences; no network/provider/UI"]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
