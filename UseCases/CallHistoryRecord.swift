//
//  CallHistoryRecord.swift
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

public struct CallHistoryRecord: Sendable {
    public let identifier: String
    /// The identity inside its original UUID store. Global rows qualify this identity without changing the store.
    public let accountRecordIdentifier: String
    public let uri: URI
    public let date: Date
    public let duration: Int
    public let isIncoming: Bool
    public let isMissed: Bool
    public let canonicalDestination: String?
    public let originAccountUUID: String?
    public let originAccountName: String?

    public init(uri: URI, date: Date, duration: Int, isIncoming: Bool, isMissed: Bool,
                canonicalDestination: String? = nil, originAccountUUID: String? = nil, originAccountName: String? = nil) {
        self.init(uri: uri, date: date, duration: duration, isIncoming: isIncoming, isMissed: isMissed,
                  canonicalDestination: canonicalDestination, originAccountUUID: originAccountUUID,
                  originAccountName: originAccountName, identityAccountUUID: nil)
    }

    private init(uri: URI, date: Date, duration: Int, isIncoming: Bool, isMissed: Bool,
                 canonicalDestination: String?, originAccountUUID: String?, originAccountName: String?, identityAccountUUID: String?) {
        let recordIdentifier = "\(uri.user)@\(uri.host)|\(date.timeIntervalSinceReferenceDate)|\(duration)|\(isIncoming ? 1 : 0)"
        accountRecordIdentifier = recordIdentifier
        identifier = identityAccountUUID.map { "\($0)|\(recordIdentifier)" } ?? recordIdentifier
        self.uri = uri
        self.date = date
        self.duration = duration
        self.isIncoming = isIncoming
        self.isMissed = isMissed
        self.canonicalDestination = canonicalDestination
        self.originAccountUUID = originAccountUUID
        self.originAccountName = originAccountName
    }

    public func qualified(accountUUID: String, accountName: String) -> CallHistoryRecord {
        CallHistoryRecord(uri: uri, date: date, duration: duration, isIncoming: isIncoming, isMissed: isMissed,
                          canonicalDestination: canonicalDestination, originAccountUUID: accountUUID,
                          originAccountName: accountName, identityAccountUUID: accountUUID)
    }

    /// Legacy number/service users enter today's plan without a historical provider host.
    /// New records retain their call-time dispatch value, including explicit numeric SIP intent.
    public var callbackDestination: String {
        if let canonicalDestination, !canonicalDestination.isEmpty { return canonicalDestination }
        if uri.host.isEmpty || isLiteralHistoryDestination(uri.user) { return uri.user }
        return URI(user: uri.user, address: uri.address, displayName: "", transport: uri.transport).stringValue
    }

    public func removingHost() -> CallHistoryRecord {
        return CallHistoryRecord(
            uri: URI(user: uri.user, host: "", displayName: uri.displayName),
            date: date,
            duration: duration,
            isIncoming: isIncoming,
            isMissed: isMissed,
            canonicalDestination: canonicalDestination,
            originAccountUUID: originAccountUUID,
            originAccountName: originAccountName
        )
    }
}

private func isLiteralHistoryDestination(_ text: String) -> Bool {
    if text.hasPrefix("+") {
        let digits = text.dropFirst()
        return (6...15).contains(digits.count) && digits.first != "0" && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
    return (1...64).contains(text.utf8.count) && text.contains(where: { $0.isASCII && $0.isNumber }) &&
        text.allSatisfy { $0.isASCII && ($0.isNumber || "*#RP".contains($0)) }
}

extension CallHistoryRecord: Equatable {
    public static func ==(lhs: CallHistoryRecord, rhs: CallHistoryRecord) -> Bool {
        return
            lhs.uri == rhs.uri &&
            lhs.date == rhs.date &&
            lhs.duration == rhs.duration &&
            lhs.isIncoming == rhs.isIncoming &&
            lhs.isMissed == rhs.isMissed &&
            lhs.identifier == rhs.identifier &&
            lhs.canonicalDestination == rhs.canonicalDestination &&
            lhs.originAccountUUID == rhs.originAccountUUID &&
            lhs.originAccountName == rhs.originAccountName
    }
}

extension CallHistoryRecord {
    public init(call: Call, originAccountName: String? = nil) {
        self.init(
            uri: call.remote,
            date: call.date,
            duration: call.duration,
            isIncoming: call.isIncoming,
            isMissed: call.isMissed,
            canonicalDestination: call.canonicalDestination ?? nil,
            originAccountUUID: call.account.uuid,
            originAccountName: originAccountName
        )
    }
}
