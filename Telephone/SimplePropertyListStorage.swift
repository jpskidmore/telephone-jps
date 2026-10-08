//
//  SimplePropertyListStorage.swift
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

import Foundation
import UseCases

final class SimplePropertyListStorage {
    private let url: URL
    private nonisolated(unsafe) let manager: FileManager

    init(url: URL, manager: FileManager) {
        self.url = url
        self.manager = manager
    }
}

extension SimplePropertyListStorage: PropertyListStorage {
    func load() throws -> [[String : Any]] {
        do {
            let plist = try PropertyListSerialization.propertyList(from: try Data(contentsOf: url), options: [], format: nil)
            guard let records = plist as? [[String: Any]], records.allSatisfy({ record in
                record["user"] is String && record["host"] is String && record["name"] is String &&
                record["date"] is Date && record["duration"] is Int &&
                record["incoming"] is Bool && record["missed"] is Bool &&
                ["port", "transport", "canonicalDestination", "originAccountUUID", "originAccountName"].allSatisfy { key in
                    record[key] == nil || record[key] is String
                } && validCanonicalHistoryDestination(record["canonicalDestination"]) &&
                (record["transport"] == nil || ["udp", "tcp", "tls"].contains(record["transport"] as? String ?? ""))
            }) else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return records
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    func save(_ plist: [[String : Any]]) throws {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: url, options: .atomic)
    }

    func delete() throws {
        do {
            try manager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Do nothing.
        }
    }
}

// Validate the stored syntax without consulting today's country/area profile.
// Routing and provider support are checked again by the current dial plan.
private func validCanonicalHistoryDestination(_ value: Any?) -> Bool {
    guard let value else { return true }
    guard let text = value as? String, !text.isEmpty,
          !text.contains(where: \.isWhitespace),
          !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
    if text.hasPrefix("+") {
        let digits = text.dropFirst()
        return (6...15).contains(digits.count) && digits.first != "0" && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
    // Short, emergency and service destinations retain their literal dispatch
    // form. Never turn them into a provider-host SIP address on a later callback.
    if (1...64).contains(text.utf8.count), text.contains(where: { $0.isASCII && $0.isNumber }),
       text.allSatisfy({ $0.isASCII && ($0.isNumber || "*#RP".contains($0)) }) { return true }
    if text.lowercased().hasPrefix("sips:") { return false }
    if text.contains("@") || text.lowercased().hasPrefix("sip:") {
        guard text.filter({ $0 == "@" }).count == 1,
              !text.contains(where: { "/\\<>\"".contains($0) }) else { return false }
        let uriText = text.lowercased().hasPrefix("sip:") ? text : "sip:\(text)"
        guard let uri = URI(uriText), !uri.user.isEmpty, !uri.host.isEmpty, !uri.host.contains("%") else { return false }
        return uri.port.isEmpty || (uri.port.allSatisfy { $0.isASCII && $0.isNumber } && (1...65535).contains(Int(uri.port) ?? 0))
    }
    // Internal SIP aliases are supported independently of telephone-number profiles.
    return text.contains(where: { $0.isASCII && $0.isLetter }) && text.allSatisfy {
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".")
    }
}

// Objective-C termination code uses the same admission barrier as all history writes.
@objc final class HistoryPersistenceCoordinator: NSObject {
    @objc static func finishPendingWrites(completion: @escaping @Sendable () -> Void) {
        CallHistoryWork.shared.finish(completion: completion)
    }

    @objc static func retryFailedWrites(completion: @escaping @Sendable (Bool) -> Void) {
        Task {
            let succeeded = await PersistentCallHistory.retryFailedWrites()
            await MainActor.run { completion(succeeded) }
        }
    }

    @objc static func resumeAcceptingWrites() { CallHistoryWork.shared.resume() }
}
