//
//  CNContactStoreContactsChangeEventSource.swift
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
import Contacts
import Foundation
import UseCases

final class CNContactStoreContactsChangeEventSource {
    private let center: NotificationCenter
    private let target: ContactsChangeEventTarget
    private let didChange: @Sendable () -> Void

    init(center: NotificationCenter, target: ContactsChangeEventTarget, didChange: @escaping @Sendable () -> Void = {}) {
        self.center = center
        self.target = target
        self.didChange = didChange
        center.addObserver(self, selector: #selector(contactsDidChange), name: .CNContactStoreDidChange, object: nil)
    }

    deinit {
        center.removeObserver(self, name: .CNContactStoreDidChange, object: nil)
    }

    @objc private func contactsDidChange(_ notification: Notification) {
        Task { [target, didChange] in
            await target.contactsDidChange()
            didChange()
        }
    }
}

// Sequence admission occurs synchronously on the producer, before the main
// actor hop. Late queued UI work cannot paint a state superseded by revocation.
private final class ContactsStatusOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func next() -> UInt64 { lock.lock(); defer { lock.unlock() }; value &+= 1; return value }
    func isLatest(_ sequence: UInt64) -> Bool { lock.lock(); defer { lock.unlock() }; return sequence == value }
}

@MainActor
final class ContactsStatusRelay {
    weak var controller: ContactsRecoveryController?
    nonisolated private let order = ContactsStatusOrder()
    nonisolated func enqueue(_ state: ContactsLoadState) {
        let sequence = order.next()
        Task { @MainActor [weak self] in
            guard let self, order.isLatest(sequence) else { return }
            controller?.receive(state)
        }
    }
}

@MainActor
@objc final class ContactsRecoveryController: NSObject {
    @objc private(set) var statusText = "Contacts: Not checked"
    @objc private(set) var actionTitle = "Check Contacts"
    @objc private(set) var actionEnabled = true
    @objc var presentationDidChange: (() -> Void)?

    private let index: LazyDiscardingContactMatchingIndex
    private let requestAccess: @Sendable () async -> Bool
    private let openSettings: () -> Void
    private let reloadHistory: () -> Void
    private let center: NotificationCenter
    private var state: ContactsLoadState = .notLoaded
    private var operation: Task<Void, Never>?
    private var refreshPending = false
    private var isBusy = false
    private var requestFailed = false

    init(index: LazyDiscardingContactMatchingIndex,
         requestAccess: @escaping @Sendable () async -> Bool,
         center: NotificationCenter = .default,
         openSettings: @escaping () -> Void = {
             if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                 NSWorkspace.shared.open(url)
             }
         }, reloadHistory: @escaping () -> Void = {}) {
        self.index = index
        self.requestAccess = requestAccess
        self.center = center
        self.openSettings = openSettings
        self.reloadHistory = reloadHistory
        super.init()
        center.addObserver(self, selector: #selector(applicationBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    deinit { center.removeObserver(self) }

    @objc nonisolated private func applicationBecameActive(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    func receive(_ state: ContactsLoadState) {
        self.state = state
        if state != .unavailable(.notDetermined) { requestFailed = false }
        updatePresentation()
        if state != .loading, state != .notLoaded { reloadHistory() }
    }

    @objc func refresh() {
        refreshPending = true
        guard operation == nil else { return }
        start(requestPermission: false)
    }

    @objc func performAction() {
        guard !isBusy else { return }
        switch state {
        case .unavailable(.denied): openSettings()
        case .unavailable(.restricted): break
        case .unavailable(.notDetermined): start(requestPermission: true)
        default: refresh()
        }
    }

    private func start(requestPermission: Bool) {
        isBusy = true
        if requestPermission { requestFailed = false }
        updatePresentation()
        operation = Task { [weak self] in
            guard let self else { return }
            let requestCompleted = requestPermission ? await requestAccess() : true
            repeat {
                refreshPending = false
                await index.refresh()
            } while refreshPending
            isBusy = false
            operation = nil
            requestFailed = !requestCompleted
            updatePresentation()
        }
    }

    private func updatePresentation() {
        actionEnabled = !isBusy
        switch state {
        case .notLoaded:
            statusText = NSLocalizedString("Contacts: Not checked", comment: "Contacts state.")
            actionTitle = NSLocalizedString("Check Contacts", comment: "Contacts recovery action.")
        case .loading:
            statusText = NSLocalizedString("Contacts: Checking…", comment: "Contacts state.")
            actionTitle = NSLocalizedString("Retry", comment: "Contacts recovery action.")
            actionEnabled = false
        case .ready:
            statusText = NSLocalizedString("Contacts: Available", comment: "Contacts state.")
            actionTitle = NSLocalizedString("Refresh", comment: "Contacts recovery action.")
        case .unavailable(.notDetermined):
            statusText = NSLocalizedString("Contacts: Access not requested. Allow access to show names.", comment: "Contacts access guidance.")
            actionTitle = NSLocalizedString("Allow Contacts", comment: "Explicit Contacts access request.")
        case .unavailable(.denied):
            statusText = NSLocalizedString("Contacts: Access denied. Enable it in System Settings.", comment: "Contacts access guidance.")
            actionTitle = NSLocalizedString("Open Settings…", comment: "Contacts access recovery.")
        case .unavailable(.restricted):
            statusText = NSLocalizedString("Contacts: Access restricted by system policy.", comment: "Contacts access guidance.")
            actionTitle = NSLocalizedString("Restricted", comment: "Contacts access is restricted.")
            actionEnabled = false
        case .unavailable(.transientWithoutCache):
            statusText = NSLocalizedString("Contacts: Could not refresh. Retry to load permitted names.", comment: "Contacts temporary failure with narrowed access.")
            actionTitle = NSLocalizedString("Retry", comment: "Contacts recovery action.")
        case .unavailable(.transient):
            statusText = NSLocalizedString("Contacts: Could not refresh. Previous matches kept; retry.", comment: "Contacts temporary failure guidance.")
            actionTitle = NSLocalizedString("Retry", comment: "Contacts recovery action.")
        }
        if requestFailed, state == .unavailable(.notDetermined) {
            statusText = NSLocalizedString("Contacts: Access request failed. Try Allow Contacts again.", comment: "Contacts request recovery.")
        }
        presentationDidChange?()
    }
}
