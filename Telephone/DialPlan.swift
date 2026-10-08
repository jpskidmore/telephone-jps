// Guided dialling plans. Pure Foundation; no SIP, Contacts or AppKit operations.
// Numbering provenance and intentionally bounded coverage: docs/DIAL_PLAN_NUMBERING.md.
import Foundation

@objcMembers
final class DialPlanAccount: NSObject {
    let uuid: String
    let name: String
    let enabled: Bool
    // online/unavailable permit outgoing calls; needsRegistration/registering wait.
    // offline means deliberately Offline; failed means a failed registration.
    let availability: String

    @objc(initWithUUID:name:enabled:availability:)
    init(uuid: String, name: String, enabled: Bool, availability: String) {
        self.uuid = uuid
        self.name = name
        self.enabled = enabled
        self.availability = availability
    }
}

@objcMembers
final class DialPlanNumber: NSObject {
    let original: String
    let canonical: String
    let destination: String
    let canonicalNumber: String?
    // telephone, emergency, short, service, sip, invalid.
    let kind: String
    let category: String
    let message: String
    var valid: Bool { kind != "invalid" }

    fileprivate init(original: String, canonical: String, kind: String, category: String,
                     message: String = "") {
        self.original = original
        self.canonical = canonical
        destination = canonical
        canonicalNumber = kind == "telephone" ? canonical : nil
        self.kind = kind
        self.category = category
        self.message = message
    }
}

@objcMembers
final class DialPlanRoute: NSObject {
    let destination: DialPlanNumber
    let accountUUID: String?
    let category: String
    let matchedPrefix: String?
    let blocked: Bool
    let canDial: Bool
    let requiresRegistration: Bool
    let message: String

    fileprivate init(destination: DialPlanNumber, accountUUID: String? = nil,
                     matchedPrefix: String? = nil, blocked: Bool = false,
                     canDial: Bool = false, requiresRegistration: Bool = false,
                     message: String) {
        self.destination = destination
        self.accountUUID = accountUUID
        category = destination.category
        self.matchedPrefix = matchedPrefix
        self.blocked = blocked
        self.canDial = canDial
        self.requiresRegistration = requiresRegistration
        self.message = message
    }
}

@MainActor
@objcMembers
final class DialPlanStore: NSObject {
    static let shared = DialPlanStore(defaults: .standard)
    static let settingsKey = "JPSDialPlanConfigurationV1"
    static let changeNotificationName = "JPSDialPlanDidChangeNotification"
    static let metadataVersion = "ofcom-2025-04-22+libphonenumber-d145763-v1"
    static let supportedCountryCodes = ["+44", "+1", "+33", "+49", "+39"]
    let defaults: UserDefaults
    private var model: DialPlanConfiguration
    private(set) var configurationError: String = ""

    var configuration: [String: Any] { model.dictionary }

    @objc(initWithDefaults:)
    init(defaults: UserDefaults) {
        self.defaults = defaults
        model = .initial
        super.init()
        guard let stored = defaults.object(forKey: Self.settingsKey) else { return }
        do {
            guard let data = stored as? Data else { throw dialPlanError("Saved dialling plans have an invalid format.") }
            let value = try JSONDecoder().decode(DialPlanConfiguration.self, from: data)
            model = try DialPlanConfiguration.validate(value.dictionary)
        } catch {
            // A damaged/newer plan must not quietly become a different, chargeable route.
            configurationError = error.localizedDescription
        }
    }

    @objc(updateConfiguration:error:)
    func updateConfiguration(_ dictionary: [String: Any]) throws {
        let next = try DialPlanConfiguration.validate(dictionary)
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.settingsKey)
        model = next
        configurationError = ""
        NotificationCenter.default.post(name: Notification.Name(Self.changeNotificationName), object: self)
    }

    // Migrate the old first-enabled default once; never change it on account reorder.
    @objc(bootstrapDefaultAccountUUID:)
    func bootstrapDefaultAccountUUID(_ uuid: String) {
        guard defaults.object(forKey: Self.settingsKey) == nil,
              configurationError.isEmpty, !uuid.isEmpty else { return }
        var value = configuration
        value["defaultAccountUUID"] = uuid
        // Emergency routing is an explicit user setting, never inferred from the default.
        try? updateConfiguration(value)
    }

    @objc(normaliseDestination:)
    func normaliseDestination(_ input: String) -> DialPlanNumber {
        DialPlanNormaliser.normalise(input, configuration: model)
    }

    @objc(resolveDestination:accounts:)
    func resolveDestination(_ input: String, accounts: [DialPlanAccount]) -> DialPlanRoute {
        let number = normaliseDestination(input)
        guard configurationError.isEmpty else {
            return DialPlanRoute(destination: number, message: "Repair the saved dialling plans before making a call. \(configurationError)")
        }
        return DialPlanResolver.resolve(number, configuration: model, accounts: accounts)
    }

    @objc(previewDestination:configuration:accounts:error:)
    func previewDestination(_ input: String, configuration: [String: Any],
                            accounts: [DialPlanAccount]) throws -> DialPlanRoute {
        let draft = try DialPlanConfiguration.validate(configuration)
        return DialPlanResolver.resolve(DialPlanNormaliser.normalise(input, configuration: draft),
                                        configuration: draft, accounts: accounts)
    }

    @objc(categoryPrefixes:)
    func categoryPrefixes(_ category: String) -> [String] {
        guard model.countryCode == "+44" else {
            return category == "international" ? ["Outside \(model.countryCode)"] : []
        }
        switch category {
        case "mobile", "landline", "premium": return UKNumberingClassification.prefixes(for: category)
        case "service": return UKNumberingClassification.prefixes(for: category) + ["Short and * / # service codes"]
        case "other": return ["+4455", "+4456", "+4470", "+4476 (except +447624)", "Unclassified UK ranges"]
        case "international": return ["Outside +44"]
        default: return []
        }
    }
}

private func dialPlanError(_ message: String) -> NSError {
    NSError(domain: "JPSDialPlanError", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

private struct DialPlanRule: Codable, Sendable {
    let id: String
    let prefix: String
    let enabled: Bool
    let target: String
    let comment: String
    var dictionary: [String: Any] {
        ["id": id, "prefix": prefix, "enabled": enabled, "target": target, "comment": comment]
    }
}

private struct DialPlanConfiguration: Codable, Sendable {
    let schemaVersion: Int
    let countryCode: String
    let areaCode: String
    let defaultAccountUUID: String
    let emergencyAccountUUID: String
    let categoryTargets: [String: String]
    let rules: [DialPlanRule]

    static let initial = DialPlanConfiguration(schemaVersion: 1, countryCode: "+44", areaCode: "01442",
                                              defaultAccountUUID: "", emergencyAccountUUID: "",
                                              categoryTargets: [:], rules: [])
    static let categories: Set<String> = ["mobile", "landline", "international", "premium", "other", "service"]
    var dictionary: [String: Any] {
        ["schemaVersion": schemaVersion, "countryCode": countryCode, "areaCode": areaCode,
         "defaultAccountUUID": defaultAccountUUID, "emergencyAccountUUID": emergencyAccountUUID,
         "categoryTargets": categoryTargets, "rules": rules.map(\.dictionary)]
    }

    static func validate(_ dictionary: [String: Any]) throws -> DialPlanConfiguration {
        let version: Int
        if let supplied = dictionary["schemaVersion"] {
            guard let number = supplied as? Int, !(supplied is String) else {
                throw dialPlanError("The dialling-plan schema version must be an integer.")
            }
            version = number
        } else { version = 1 }
        guard version == 1 else { throw dialPlanError("This dialling-plan version is not supported. Update the app before using it.") }
        guard let country = dictionary["countryCode"] as? String,
              let profile = NumberingProfile.profiles[country] else {
            throw dialPlanError("Choose a supported default country: +44, +1, +33, +49 or +39.")
        }
        guard let area = dictionary["areaCode"] as? String,
              profile.validArea(area) else { throw dialPlanError("Enter an area code for \(country), or leave it blank.") }
        guard let defaultUUID = dictionary["defaultAccountUUID"] as? String,
              let emergencyUUID = dictionary["emergencyAccountUUID"] as? String,
              validTarget(defaultUUID, allowEmpty: true),
              validTarget(emergencyUUID, allowEmpty: true),
              emergencyUUID != "block", defaultUUID != "block" else {
            throw dialPlanError("Default and emergency routes must name a connection, or be left unconfigured.")
        }
        guard let targets = dictionary["categoryTargets"] as? [String: String],
              targets.allSatisfy({ categories.contains($0.key) && validTarget($0.value, allowEmpty: true) }) else {
            throw dialPlanError("Each category must use a connection, Default or Block.")
        }
        guard let suppliedRules = dictionary["rules"] as? [[String: Any]], suppliedRules.count <= 500 else {
            throw dialPlanError("The exceptions must be a list of at most 500 rules.")
        }
        var prefixes = Set<String>(), identifiers = Set<String>(), rules: [DialPlanRule] = []
        for (index, value) in suppliedRules.enumerated() {
            guard let suppliedPrefix = value["prefix"] as? String,
                  let prefix = profile.canonicalPrefix(suppliedPrefix),
                  let enabled = value["enabled"] as? Bool,
                  let target = value["target"] as? String, validTarget(target, allowEmpty: false),
                  let comment = value["comment"] as? String, comment.count <= 20 else {
                throw dialPlanError("Exception \(index + 1) needs a valid prefix, connection or Block, enabled flag and comment of at most 20 characters.")
            }
            guard prefixes.insert(prefix).inserted else { throw dialPlanError("The prefix \(prefix) is already used. Each exception must have a distinct prefix.") }
            let identifier = value["id"] as? String ?? UUID().uuidString
            guard !identifier.isEmpty, identifiers.insert(identifier).inserted else {
                throw dialPlanError("Exception identifiers must be distinct.")
            }
            rules.append(DialPlanRule(id: identifier, prefix: prefix, enabled: enabled, target: target, comment: comment))
        }
        return DialPlanConfiguration(schemaVersion: version, countryCode: country, areaCode: area,
                                     defaultAccountUUID: defaultUUID, emergencyAccountUUID: emergencyUUID,
                                     categoryTargets: targets, rules: rules)
    }

    private static func validTarget(_ target: String, allowEmpty: Bool) -> Bool {
        (allowEmpty && target.isEmpty) || (!target.isEmpty && target == target.trimmingCharacters(in: .whitespacesAndNewlines)
                                         && !target.contains(where: { $0.isWhitespace || $0.isNewline }) && target.count <= 128)
    }
}

private struct NumberingProfile: Sendable {
    let countryCode: String
    let nationalPrefix: String
    let internationalPrefix: String
    let nationalLengths: ClosedRange<Int>

    // Bounded metadata-derived country/trunk support, not an allocation/reachability database.
    static let profiles: [String: NumberingProfile] = [
        "+44": .init(countryCode: "+44", nationalPrefix: "0", internationalPrefix: "00", nationalLengths: 9...10),
        "+1": .init(countryCode: "+1", nationalPrefix: "1", internationalPrefix: "011", nationalLengths: 10...10),
        "+33": .init(countryCode: "+33", nationalPrefix: "0", internationalPrefix: "00", nationalLengths: 9...9),
        "+49": .init(countryCode: "+49", nationalPrefix: "0", internationalPrefix: "00", nationalLengths: 5...13),
        "+39": .init(countryCode: "+39", nationalPrefix: "", internationalPrefix: "00", nationalLengths: 6...12)
    ]

    func validArea(_ area: String) -> Bool {
        if area.isEmpty { return true }
        guard asciiDigits(area) else { return false }
        switch countryCode {
        case "+44": return (3...7).contains(area.count) && (area.hasPrefix("01") || area.hasPrefix("02"))
        case "+1": return area.count == 3 && "23456789".contains(area.first!)
        case "+33": return area.count == 2 && area.first == "0" && "12345".contains(area.last!)
        case "+49": return (2...6).contains(area.count) && area.hasPrefix("0") && area.dropFirst().first != "0"
        case "+39": return (2...6).contains(area.count) && area.hasPrefix("0") && area.dropFirst().first != "0"
        default: return false
        }
    }

    func areaSignificantDigits(_ area: String) -> String {
        !nationalPrefix.isEmpty && area.hasPrefix(nationalPrefix)
            ? String(area.dropFirst(nationalPrefix.count)) : area
    }

    func validNational(_ number: String) -> Bool {
        guard asciiDigits(number) else { return false }
        if countryCode == "+44" {
            if number.hasPrefix("1") || number.hasPrefix("2") { return (9...10).contains(number.count) }
            if number.hasPrefix("800") { return [7, 9, 10].contains(number.count) }
            if number.hasPrefix("90") || number.hasPrefix("91") || number.hasPrefix("98") { return [7, 10].contains(number.count) }
            return number.count == 10
        }
        return nationalLengths.contains(number.count)
    }

    func canonicalPrefix(_ input: String) -> String? {
        // Prefixes are literal. No whitespace, separators or hidden wildcard syntax.
        guard !input.isEmpty, input == input.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        var prefix = input.uppercased()
        if prefix.hasPrefix("+") {
            let digits = String(prefix.dropFirst())
            return asciiDigits(digits) && digits.first != "0" && digits.count <= 15 ? prefix : nil
        }
        if prefix.hasPrefix(internationalPrefix) && prefix.count > internationalPrefix.count {
            let digits = String(prefix.dropFirst(internationalPrefix.count))
            return asciiDigits(digits) && digits.first != "0" && digits.count <= 15 ? "+" + digits : nil
        }
        if !nationalPrefix.isEmpty, prefix.hasPrefix(nationalPrefix), asciiDigits(prefix) {
            prefix = countryCode + prefix.dropFirst(nationalPrefix.count)
            return prefix.dropFirst().count <= 15 ? prefix : nil
        }
        if countryCode == "+39", prefix.hasPrefix("0"), asciiDigits(prefix) {
            return countryCode.dropFirst().count + prefix.count <= 15 ? countryCode + prefix : nil
        }
        let permitted = Set("0123456789*#RP")
        return prefix.count <= 15 && prefix.allSatisfy({ permitted.contains($0) }) ? prefix : nil
    }
}

private func asciiDigits(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
}

private enum DialPlanNormaliser {
    static func normalise(_ input: String, configuration: DialPlanConfiguration) -> DialPlanNumber {
        let entered = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed: String
        if entered.lowercased().hasPrefix("sip://") {
            trimmed = "sip:" + entered.dropFirst(6)
        } else if entered.lowercased().hasPrefix("tel://") {
            trimmed = "tel:" + entered.dropFirst(6)
        } else { trimmed = entered }
        func result(_ canonical: String, _ kind: String, _ category: String, _ message: String = "") -> DialPlanNumber {
            DialPlanNumber(original: input, canonical: canonical, kind: kind, category: category, message: message)
        }
        func invalid(_ message: String) -> DialPlanNumber { result(trimmed, "invalid", "invalid", message) }
        guard !trimmed.isEmpty else { return invalid("Enter a number or SIP address.") }
        guard !trimmed.contains(where: { $0.isNewline || $0 == "\t" }),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return invalid("A destination cannot contain line breaks or control characters.")
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("sips:") {
            return invalid("Secure sips: URI schemes are not supported. Use a supported SIP address with the connection's TLS transport configured.")
        }
        if lower.hasPrefix("sip:") || trimmed.contains("@") {
            if let error = sipValidationError(trimmed) { return invalid(error) }
            return result(trimmed, "sip", "sip")
        }
        var candidate = trimmed
        let telephoneLink = lower.hasPrefix("tel:")
        if telephoneLink {
            guard let decoded = String(trimmed.dropFirst(4)).removingPercentEncoding else {
                return invalid("The telephone link contains invalid percent encoding.")
            }
            candidate = decoded
            guard !candidate.contains(where: { $0.isNewline || $0 == "\t" }), !candidate.contains(";") && !candidate.contains("?") else {
                return invalid("This telephone link contains unsupported parameters or control characters.")
            }
        }
        if !telephoneLink, candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_" || $0 == "-" || $0 == ".") }),
           candidate.contains(where: \.isLetter) {
            return result(trimmed, "sip", "sip")
        }
        let separators: Set<Character> = [" ", "(", ")", "-", ".", "\u{00a0}", "\u{202f}"]
        let compact = String(candidate.filter { !separators.contains($0) })
        guard !compact.isEmpty else { return invalid("Enter a number or SIP address.") }
        if compact == "999" || compact == "112" { return result(compact, "emergency", "emergency") }
        let serviceCharacters = Set("0123456789*#RP")
        if compact.contains("*") || compact.contains("#") || compact.contains("R") || compact.contains("P") {
            guard compact.count <= 64 && compact.allSatisfy({ serviceCharacters.contains($0) }),
                  compact.contains(where: { $0.isNumber }) else { return invalid("Enter a valid service code; unsupported characters are not removed.") }
            return result(compact, "service", "service", compact.contains("R") || compact.contains("P") ? "Pause/recall syntax is preserved for the selected connection; it is not converted into post-connect DTMF." : "")
        }
        guard asciiDigits(compact) || (compact.hasPrefix("+") && asciiDigits(String(compact.dropFirst()))) else {
            return invalid("Use digits and ordinary number separators, or enter an explicit SIP address. Unsupported characters are not removed.")
        }
        guard let profile = NumberingProfile.profiles[configuration.countryCode] else { return invalid("Select a supported default country.") }
        if !compact.hasPrefix("+") && compact.count <= 5 { return result(compact, "short", "service") }
        if configuration.countryCode == "+44", !compact.hasPrefix("+"),
           compact.hasPrefix("116") || compact.hasPrefix("118") || compact.hasPrefix("18001") || compact.hasPrefix("18002") {
            return result(compact, "service", "service")
        }
        var international: String
        if compact.hasPrefix("+") {
            international = compact
        } else if compact.hasPrefix(profile.internationalPrefix) {
            international = "+" + compact.dropFirst(profile.internationalPrefix.count)
        } else {
            var national = compact
            if !profile.nationalPrefix.isEmpty && national.hasPrefix(profile.nationalPrefix) && national.count > 5 {
                national = String(national.dropFirst(profile.nationalPrefix.count))
            } else if !profile.nationalLengths.contains(national.count)
                        || profile.countryCode == "+49"
                        || (profile.countryCode == "+39" && !national.hasPrefix("0")
                            && !(national.hasPrefix("3") && (9...10).contains(national.count))) {
                guard !configuration.areaCode.isEmpty else { return invalid("Set a default area code, or enter a national or international number.") }
                national = profile.areaSignificantDigits(configuration.areaCode) + national
            }
            guard profile.validNational(national) else { return invalid("That number is incomplete or too long for \(profile.countryCode). Check the number and default area code.") }
            international = profile.countryCode + national
        }
        guard validInternational(international) else { return invalid("Enter a complete international number with a recognised country calling code and at most 15 digits.") }
        if let destinationProfile = NumberingProfile.profiles.values.first(where: { international.hasPrefix($0.countryCode) }) {
            let national = String(international.dropFirst(destinationProfile.countryCode.count))
            guard destinationProfile.validNational(national) else { return invalid("That number has an invalid length for \(destinationProfile.countryCode).") }
        }
        return result(international, "telephone", classify(international, configuration: configuration))
    }

    private static func sipValidationError(_ input: String) -> String? {
        // The bridge represents only user, host, port and transport. Reject any
        // syntax it would silently discard before the native parser sees it.
        guard !input.contains(where: \.isWhitespace), !input.contains("<"), !input.contains(">"), !input.contains("\"") else {
            return "Enter a SIP address without spaces or a display-name wrapper."
        }
        let address: String
        if let colon = input.firstIndex(of: ":"), input[..<colon].lowercased() == "sip" {
            address = String(input[input.index(after: colon)...])
        } else {
            if let colon = input.firstIndex(of: ":"), let at = input.firstIndex(of: "@"), colon < at {
                return "Only sip: addresses are supported."
            }
            address = input
        }
        guard address.filter({ $0 == "@" }).count == 1,
              let at = address.lastIndex(of: "@"), at != address.startIndex else {
            return "Enter a complete SIP address with one user and host."
        }
        let hostAndParameters = String(address[address.index(after: at)...])
        guard !hostAndParameters.contains("?") else {
            return "SIP URI headers are not supported. Remove the question-mark parameters."
        }
        let parts = hostAndParameters.split(separator: ";", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 2,
              parts.count == 1 || ["transport=udp", "transport=tcp", "transport=tls"].contains(parts[1].lowercased()) else {
            return "Only one SIP parameter is supported: transport=udp, tcp or tls. Other or duplicate parameters would change this address."
        }
        let hostAndPort = String(parts[0])
        var host: String, port: String?
        if hostAndPort.hasPrefix("[") {
            guard let close = hostAndPort.firstIndex(of: "]") else { return "Close the IPv6 address with a square bracket." }
            host = String(hostAndPort[hostAndPort.index(after: hostAndPort.startIndex)..<close])
            guard host.contains(":"), host.allSatisfy({ "0123456789abcdefABCDEF:.".contains($0) }) else {
                return "Enter an IPv6 address in square brackets without unsupported scope syntax."
            }
            // inet_pton parses bytes only; it does not resolve DNS or open a socket.
            var ipv6 = in6_addr()
            guard host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 else {
                return "Enter a complete IPv6 SIP host address."
            }
            let suffix = String(hostAndPort[hostAndPort.index(after: close)...])
            guard suffix.isEmpty || suffix.hasPrefix(":") else { return "Only a numeric port may follow an IPv6 address." }
            port = suffix.isEmpty ? nil : String(suffix.dropFirst())
        } else {
            guard hostAndPort.filter({ $0 == ":" }).count <= 1 else { return "Put an IPv6 SIP host in square brackets." }
            let components = hostAndPort.split(separator: ":", omittingEmptySubsequences: false)
            guard !components.isEmpty else { return "Enter a SIP host name or IP address." }
            host = String(components[0])
            port = components.count == 2 ? String(components[1]) : nil
            let labels = (host.hasSuffix(".") ? String(host.dropLast()) : host).split(separator: ".", omittingEmptySubsequences: false)
            let alphanumeric = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            guard !host.isEmpty, host.count <= 253, labels.allSatisfy({ label in
                !label.isEmpty && label.count <= 63 && alphanumeric.contains(label.first!) && alphanumeric.contains(label.last!)
                    && label.allSatisfy({ alphanumeric.contains($0) || $0 == "-" })
            }) else { return "Enter a valid SIP host name or IP address." }
        }
        if let port, !asciiDigits(port) || Int(port).map({ !(1...65535).contains($0) }) != false {
            return "Enter a SIP port from 1 to 65535."
        }
        return nil
    }

    private static func validInternational(_ value: String) -> Bool {
        let digits = String(value.dropFirst())
        guard value.first == "+", asciiDigits(digits), (6...15).contains(digits.count), digits.first != "0" else { return false }
        return countryCodes.contains { digits.hasPrefix($0) && digits.count > $0.count + 3 }
    }

    private static func classify(_ value: String, configuration: DialPlanConfiguration) -> String {
        guard value.hasPrefix(configuration.countryCode) else { return "international" }
        guard configuration.countryCode == "+44" else { return "other" }
        return UKNumberingClassification.match(value)?.category ?? "other"
    }

    // Country calling-code presence from pinned libphonenumber metadata; includes
    // non-geographic international services. Allocation and reachability are not inferred.
    private static let countryCodes = "1 7 20 27 30 31 32 33 34 36 39 40 41 43 44 45 46 47 48 49 51 52 53 54 55 56 57 58 60 61 62 63 64 65 66 81 82 84 86 90 91 92 93 94 95 98 211 212 213 216 218 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 260 261 262 263 264 265 266 267 268 269 290 291 297 298 299 350 351 352 353 354 355 356 357 358 359 370 371 372 373 374 375 376 377 378 380 381 382 383 385 386 387 389 420 421 423 500 501 502 503 504 505 506 507 508 509 590 591 592 593 594 595 596 597 598 599 670 672 673 674 675 676 677 678 679 680 681 682 683 685 686 687 688 689 690 691 692 800 808 850 852 853 855 856 870 878 880 881 882 883 886 888 960 961 962 963 964 965 966 967 968 970 971 972 973 974 975 976 977 979 992 993 994 995 996 998".split(separator: " ").map(String.init)
}

private enum UKNumberingClassification {
    // Ordered matching is derived by specificity, not array order.
    static let ranges: [(prefix: String, category: String)] = [
        ("+441", "landline"), ("+442", "landline"),
        ("+4471", "mobile"), ("+4472", "mobile"), ("+4473", "mobile"), ("+4474", "mobile"),
        ("+4475", "mobile"), ("+4477", "mobile"), ("+4478", "mobile"), ("+4479", "mobile"), ("+447624", "mobile"),
        ("+4490", "premium"), ("+4491", "premium"), ("+4498", "premium"),
        ("+4430", "service"), ("+4433", "service"), ("+4434", "service"), ("+4437", "service"),
        ("+4480", "service"), ("+44843", "service"), ("+44844", "service"), ("+44845", "service"),
        ("+44870", "service"), ("+44871", "service"), ("+44872", "service"), ("+44873", "service"),
        ("+4455", "other"), ("+4456", "other"), ("+4470", "other"), ("+4476", "other")
    ]

    static func match(_ value: String) -> (prefix: String, category: String)? {
        ranges.filter { value.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }
    }
    static func prefixes(for category: String) -> [String] { ranges.filter { $0.category == category }.map(\.prefix) }
}

private enum DialPlanResolver {
    @MainActor
    static func resolve(_ number: DialPlanNumber, configuration: DialPlanConfiguration,
                        accounts: [DialPlanAccount]) -> DialPlanRoute {
        guard number.valid else { return DialPlanRoute(destination: number, message: number.message) }
        var matchedPrefix: String?
        let target: String
        if number.kind == "emergency" {
            target = configuration.emergencyAccountUUID
        } else {
            let categoryTarget = configuration.categoryTargets[number.category] ?? ""
            let custom = configuration.rules.filter { $0.enabled && number.canonical.hasPrefix($0.prefix) }
                .max { $0.prefix.count < $1.prefix.count }
            let categoryPrefix = configuration.countryCode == "+44" && number.kind == "telephone" && !categoryTarget.isEmpty
                ? UKNumberingClassification.match(number.canonical)?.prefix : nil
            if let prefix = categoryPrefix, prefix.count > (custom?.prefix.count ?? 0) {
                matchedPrefix = prefix
                target = categoryTarget
            } else if let custom {
                // A precise explicit exception wins a tie with the generated category.
                matchedPrefix = custom.prefix
                target = custom.target
            } else {
                target = categoryTarget.isEmpty ? configuration.defaultAccountUUID : categoryTarget
            }
        }
        if target == "block" {
            return DialPlanRoute(destination: number, matchedPrefix: matchedPrefix, blocked: true, message: "Blocked by the dialling plan.")
        }
        guard !target.isEmpty else {
            return DialPlanRoute(destination: number, matchedPrefix: matchedPrefix,
                                 message: number.kind == "emergency" ? "Choose an emergency connection in Dialling Plans. No other connection will be used." : "Choose a default connection or a route for this number.")
        }
        let matches = accounts.filter { $0.uuid == target }
        guard matches.count == 1, let account = matches.first else {
            return DialPlanRoute(destination: number, accountUUID: target, matchedPrefix: matchedPrefix,
                                 message: matches.isEmpty ? "The selected connection was removed. Choose another route." : "The selected connection has an ambiguous identity. Repair the accounts before dialling.")
        }
        guard account.enabled else {
            return DialPlanRoute(destination: number, accountUUID: target, matchedPrefix: matchedPrefix, message: "\(account.name) is disabled. No other connection will be used.")
        }
        switch account.availability {
        case "online", "unavailable":
            return DialPlanRoute(destination: number, accountUUID: target, matchedPrefix: matchedPrefix, canDial: true, message: "Use \(account.name).")
        case "registering", "needsRegistration":
            return DialPlanRoute(destination: number, accountUUID: target, matchedPrefix: matchedPrefix, canDial: true, requiresRegistration: true, message: "Wait for \(account.name) to register.")
        case "offline":
            return DialPlanRoute(destination: number, accountUUID: target, matchedPrefix: matchedPrefix, message: "\(account.name) is Offline. Bring it online to make this call; no other connection will be used.")
        default:
            return DialPlanRoute(destination: number, accountUUID: target, matchedPrefix: matchedPrefix, message: "\(account.name) is not available. No other connection will be used.")
        }
    }
}
