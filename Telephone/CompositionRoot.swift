//
//  CompositionRoot.swift
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

import Contacts
import Foundation
import StoreKit
import UseCases
import Domain

@MainActor
final class CompositionRoot: NSObject {
    @objc let userAgent: AKSIPUserAgent
    @objc let preferencesController: PreferencesController
    @objc let ringtonePlayback: RingtonePlaybackUseCase
    @objc let storeWindowPresenter: StoreWindowPresenter
    @objc let purchaseReminder: PurchaseReminderUseCase
    @objc let userAgentStart: UseCase
    @objc let settingsMigration: ProgressiveSettingsMigration
    @objc let orphanLogFileRemoval: OrphanLogFileRemoval
    @objc let workstationSleepStatus: WorkspaceSleepStatus
    @objc let callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    @objc let callHistoryPurchaseCheckUseCaseFactory: AsyncCallHistoryPurchaseCheckUseCaseFactory
    @objc let logFileURL: LogFileURL
    @objc let defaultAppSettings: DefaultAppSettings
    @objc let helpMenuActionTarget: HelpMenuActionTarget
    @objc let diallerContacts: JPSDiallerContacts
    @objc let accountControllers: AccountControllers
    @objc let nameServers: NameServers?
    private let defaults: UserDefaults

    private let storeEventSource: SKPaymentQueueStoreEventSource
    private let userAgentEventSource: AKSIPUserAgentEventSource
    private let devicesChangeEventSource: CoreAudioSystemAudioDevicesChangeEventSource
    private let soundIOChangeEventSource: CoreAudioDefaultSystemSoundIOChangeEventSource
    private let accountsEventSource: PreferencesControllerAccountsEventSource
    private let callEventSource: AKSIPCallEventSource
    private let contactsRecoveryController: ContactsRecoveryController
    private let contactsChangeEventSource: Any
    private let dayChangeEventSource: NSCalendarDayChangeEventSource

    @objc func setContactCompletionSuspended(_ suspended: Bool) {
        diallerContacts.setSuspended(suspended)
        if !suspended { contactsRecoveryController.refresh() }
    }

    @objc init(preferencesControllerDelegate: PreferencesControllerDelegate, nameServersChangeEventTarget: NameServersChangeEventTarget, storeEventTarget: ObjCStoreEventTarget) {
        userAgent = AKSIPUserAgent.shared()
        defaults = UserDefaults.standard

        let systemAudioDevicesFactory = CoreAudioSystemAudioDevicesFactory(objectIDs: CoreAudioDevicesAudioObjectIDs())

        let useCaseFactory = DefaultUseCaseFactory(factory: systemAudioDevicesFactory, settings: defaults)

        let soundIOFactory = PreferredSoundIOFactory(
            devicesFactory: systemAudioDevicesFactory,
            defaultIOFactory: CoreAudioDefaultSystemSoundIOFactory(defaultIO: CoreAudioDefaultIO()),
            settings: defaults
        )

        let soundFactory = SimpleSoundFactory(
            load: SettingsRingtoneSoundConfigurationLoadUseCase(settings: defaults, factory: soundIOFactory),
            factory: NSSoundToSoundAdapterFactory()
        )

        ringtonePlayback = ConditionalRingtonePlaybackUseCase(
            origin: DefaultRingtonePlaybackUseCase(
                factory: RepeatingSoundFactory(
                    soundFactory: soundFactory,
                    timerFactory: FoundationToUseCasesTimerAdapterFactory()
                )
            ),
            delegate: userAgent
        )

        let productsEventTargets = ProductsEventTargets()

        let storeViewController = StoreViewController(
            target: NullStoreViewEventTarget(), workspace: NSWorkspace.shared
        )
        let products = SKProductsRequestToProductsAdapter(expected: ExpectedProducts(), target: productsEventTargets)
        let store = SKPaymentQueueToStoreAdapter(queue: SKPaymentQueue.default(), products: products)
        #if LOCAL_PRO_BUILD
        let receipt: Receipt = LocalProReceipt()
        #else
        let receipt: Receipt = BundleReceipt(bundle: Bundle.main, gateway: ReceiptXPCGateway())
        #endif
        let storeViewEventTarget = DefaultStoreViewEventTarget(
            factory: DefaultStoreUseCaseFactory(
                products: products,
                store: store,
                receipt: receipt,
                targets: productsEventTargets
            ),
            purchaseRestoration: PurchaseRestorationUseCase(store: store),
            receiptRefresh: ReceiptRefreshUseCase(),
            presenter: DefaultStoreViewPresenter(output: storeViewController)
        )
        storeViewController.updateTarget(storeViewEventTarget)

        storeWindowPresenter = StoreWindowPresenter(controller: StoreWindowController(contentViewController: storeViewController))

        purchaseReminder = PurchaseReminderUseCase(
            accounts: SettingsAccounts(settings: defaults),
            receipt: receipt,
            settings: UserDefaultsPurchaseReminderSettings(defaults: defaults),
            now: Date(),
            version: Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String,
            output: storeWindowPresenter
        )

        userAgentStart = UserAgentStartUseCase(agent: userAgent, factory: PurchaseCheckUseCaseFactory(receipt: receipt))

        let storeEventTargets = StoreEventTargets(
            targets: [storeViewEventTarget, ObjCStoreEventTargetAdapter(target: storeEventTarget)]
        )

        storeEventSource = SKPaymentQueueStoreEventSource(
            queue: SKPaymentQueue.default(),
            target: ReceiptValidatingStoreEventTarget(origin: storeEventTargets, receipt: receipt)
        )

        let soundIOSelection = QueuedSoundIOSelectionUseCase(
            devicesFactory: systemAudioDevicesFactory,
            defaultIOFactory: CoreAudioDefaultSystemSoundIOFactory(defaultIO: CoreAudioDefaultIO()),
            settings: defaults, agent: userAgent
        )
        let userAgentEventsUserAgentSoundIOSelection = UserAgentEventsUserAgentSoundIOSelectionUseCase(
            useCase: soundIOSelection, calls: userAgent
        )
        userAgent.soundIOSelectionRetry = { [weak soundIOSelection] in
            guard let soundIOSelection else { return false }
            do {
                try soundIOSelection.execute()
                return true
            } catch {
                return false
            }
        }

        let userAgentSoundIOSelection = AudioDevicesEventsUserAgentSoundIOSelectionUseCase(
            origin: userAgentEventsUserAgentSoundIOSelection
        )

        preferencesController = PreferencesController(
            delegate: preferencesControllerDelegate,
            userAgent: userAgent,
            soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget(
                useCaseFactory: useCaseFactory,
                presenterFactory: PresenterFactory(),
                userAgentSoundIOSelection: userAgentSoundIOSelection,
                ringtoneOutputUpdate: RingtoneOutputUpdateUseCase(playback: ringtonePlayback),
                ringtoneSoundPlayback: DefaultSoundPlaybackUseCase(factory: soundFactory)
            )
        )

        settingsMigration = ProgressiveSettingsMigration(
            settings: defaults, factory: DefaultSettingsMigrationFactory(settings: defaults)
        )

        let applicationDataLocations = DirectoryCreatingApplicationDataLocations(
            origin: SimpleApplicationDataLocations(manager: FileManager.default, bundle: Bundle.main),
            manager: FileManager.default
        )

        orphanLogFileRemoval = OrphanLogFileRemoval(locations: applicationDataLocations, manager: FileManager.default)

        workstationSleepStatus = WorkspaceSleepStatus(workspace: NSWorkspace.shared)

        userAgentEventSource = AKSIPUserAgentEventSource(
            target: UserAgentEventTargets(
                targets: [
                    userAgentEventsUserAgentSoundIOSelection,
                    BackgroundActivityUserAgentEventTarget(process: ProcessInfo.processInfo)
                ]
            ),
            agent: userAgent
        )

        let background = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".background-queue", qos: .userInitiated)

        devicesChangeEventSource = CoreAudioSystemAudioDevicesChangeEventSource(
            target: MainQueueAudioDeviceEvents(origin: SystemAudioDevicesChangeEventTargets(
                targets: [
                    UserAgentAudioDeviceUpdateUseCase(agent: userAgent),
                    userAgentSoundIOSelection,
                    PreferencesSoundIOUpdater(preferences: preferencesController)
                ]
            )),
            queue: background
        )

        soundIOChangeEventSource = CoreAudioDefaultSystemSoundIOChangeEventSource(
            target: MainQueueDefaultSoundEvents(origin: userAgentSoundIOSelection), queue: background
        )

        let callHistories = DefaultCallHistories(
            factory: NotifyingCallHistoryFactory(
                origin: ReversedCallHistoryFactory(
                    origin: PersistentCallHistoryFactory(
                        history: TruncatingCallHistoryFactory(limit: 1000),
                        storage: SimplePropertyListStorageFactory(manager: FileManager.default),
                        locations: applicationDataLocations
                    )
                )
            )
        )

        let historyAccountCatalog = CallHistoryAccountCatalog()
        accountsEventSource = PreferencesControllerAccountsEventSource(
            center: NotificationCenter.default, target: CallHistoriesHistoryRemoveUseCase(histories: callHistories)
        )

        callEventSource = AKSIPCallEventSource(
            center: NotificationCenter.default,
            target: CallEventTargets(
                targets: [
                    CallHistoryCallEventTarget(
                        histories: callHistories, factory: DefaultCallHistoryRecordAddUseCaseFactory(),
                        accountName: { historyAccountCatalog.name(forUUID: $0) }
                    ),
                    MusicPlayerCallEventTarget(
                        player: SettingsMusicPlayer(
                            origin: CallsMusicPlayer(
                                origin: AvailableMusicPlayers(factory: MusicPlayerFactory()), calls: userAgent
                            ),
                            settings: SimpleMusicPlayerSettings(settings: defaults)
                        )
                    ),
                    RingtonePlaybackCallEventTarget(playback: ringtonePlayback),
                    UserAttentionRequestCallEventTarget(
                        request: CallsUserAttentionRequest(
                            origin: ApplicationUserAttentionRequest(
                                application: NSApp, center: NotificationCenter.default
                            ),
                            calls: userAgent
                        )
                    )
                ]
            )
        )

        let contactsAdapter = CNContactStoreToContactsAdapter(store: CNContactStore())
        let completion = JPSDiallerContacts(authorization: { CNContactStore.authorizationStatus(for: .contacts) == .authorized })
        diallerContacts = completion
        let contactsRelay = ContactsStatusRelay()
        let contactMatchingSettings = SimpleContactMatchingSettings(settings: defaults)
        let contactMatchingIndex = LazyDiscardingContactMatchingIndex(
            factory: SimpleContactMatchingIndexFactory(
                contacts: contactsAdapter, settings: contactMatchingSettings
            ), stateDidChange: { state in
                contactsRelay.enqueue(state)
            }, completionTicket: { completion.currentTicket() },
            completionInvalidated: { completion.invalidate() },
            completionDidLoad: { ticket, snapshot in _ = completion.enqueue(ticket, snapshot: snapshot) }
        )

        let dayChangeEventTargets = DayChangeEventTargets()
        let contactsRecovery = ContactsRecoveryController(
            index: contactMatchingIndex,
            requestAccess: { await contactsAdapter.requestAccessIfNeeded() },
            reloadHistory: { dayChangeEventTargets.dayDidChange() },
            completionInvalidated: { completion.invalidate() }
        )
        contactsRecoveryController = contactsRecovery
        contactsRelay.controller = contactsRecovery
        preferencesController.generalPreferencesViewController.contactsRecoveryController = contactsRecovery
        contactsChangeEventSource = CNContactStoreContactsChangeEventSource(
            center: NotificationCenter.default, target: contactMatchingIndex,
            willChange: { completion.invalidate() }, didChange: { Task { @MainActor in contactsRelay.controller?.refresh() } }
        )
        dayChangeEventSource = NSCalendarDayChangeEventSource(center: NotificationCenter.default, target: dayChangeEventTargets)

        callHistoryViewEventTargetFactory = AsyncCallHistoryViewEventTargetFactory(
            origin: CallHistoryViewEventTargetFactory(
                histories: callHistories,
                index: contactMatchingIndex,
                settings: contactMatchingSettings,
                receipt: receipt,
                dateFormatter: ShortRelativeDateTimeFormatter(),
                durationFormatter: DurationFormatter(),
                storeEventTargets: storeEventTargets,
                dayChangeEventTargets: dayChangeEventTargets,
                accountCatalog: historyAccountCatalog
            )
        )

        callHistoryPurchaseCheckUseCaseFactory = AsyncCallHistoryPurchaseCheckUseCaseFactory(
            origin: CallHistoryPurchaseCheckUseCaseFactory(histories: callHistories, receipt: receipt)
        )

        logFileURL = LogFileURL(locations: applicationDataLocations, filename: "Telephone.log")

        defaultAppSettings = DefaultAppSettings(settings: defaults)

        helpMenuActionTarget = HelpMenuActionTarget(
            logFileURL: logFileURL,
            fileBrowser: NSWorkspace.shared,
            clipboard: NSPasteboard.general,
            settings: AppSettings(
                settings: defaults,
                defaults: defaultAppSettings.defaults,
                accountDefaults: DefaultAppSettings.accountDefaults
            )
        )

        accountControllers = AccountControllers()

        nameServers = NameServers(bundle: Bundle.main, target: nameServersChangeEventTarget)
    }
}

// CoreAudio delivers on its listener queue. Move the complete ordered fanout to
// main before either refresh or selection admits work to the SDK control queue.
// Dispatch preserves listener delivery order; CoreAudio queries remain on the worker.
@MainActor
final class MainQueueAudioDeviceEvents: SystemAudioDevicesChangeEventTarget {
    private let origin: SystemAudioDevicesChangeEventTarget
    init(origin: SystemAudioDevicesChangeEventTarget) { self.origin = origin }
    nonisolated func systemAudioDevicesDidUpdate() {
        DispatchQueue.main.async { self.origin.systemAudioDevicesDidUpdate() }
    }
}

@MainActor
final class MainQueueDefaultSoundEvents: DefaultSystemSoundIOChangeEventTarget {
    private let origin: DefaultSystemSoundIOChangeEventTarget
    init(origin: DefaultSystemSoundIOChangeEventTarget) { self.origin = origin }
    nonisolated func defaultSystemSoundIODidUpdate() {
        DispatchQueue.main.async { self.origin.defaultSystemSoundIODidUpdate() }
    }
}

// Capture only immutable preference strings on main. Every CoreAudio query,
// native UID enumeration and SDK driver open belongs to the lifecycle worker.
protocol SoundIOSelectionAgent: AnyObject {
    var isStarted: Bool { get }
    func performAudioSelection(_ operation: @escaping (UInt) -> Int32) -> Bool
    func isAudioSelectionCurrent(_ revision: UInt) -> Bool
    func setSoundInputDevice(_ input: Int, soundOutputDevice output: Int) -> Bool
    func reportAudioSelectionFailure()
}

extension AKSIPUserAgent: SoundIOSelectionAgent {}

@MainActor
final class QueuedSoundIOSelectionUseCase: ThrowingUseCase {
    private let devicesFactory: SystemAudioDevicesFactory
    private let defaultIOFactory: SystemSoundIOFactory
    private let settings: KeyValueSettings
    private let agent: SoundIOSelectionAgent
    private let userAgentDevices: () throws -> [Domain.UserAgentAudioDevice]

    init(devicesFactory: SystemAudioDevicesFactory, defaultIOFactory: SystemSoundIOFactory,
         settings: KeyValueSettings, agent: SoundIOSelectionAgent,
         userAgentDevices: @escaping () throws -> [Domain.UserAgentAudioDevice] = { try UserAgentAudioDevices().all }) {
        self.devicesFactory = devicesFactory
        self.defaultIOFactory = defaultIOFactory
        self.settings = settings
        self.agent = agent
        self.userAgentDevices = userAgentDevices
    }

    nonisolated func execute() throws {
        if Thread.isMainThread {
            MainActor.assumeIsolated { executeOnMain() }
        } else {
            DispatchQueue.main.async { self.executeOnMain() }
        }
    }

    private func executeOnMain() {
        guard agent.isStarted else { return }
        let preferences = AudioSelectionPreferences(settings: settings)
        let devicesFactory = devicesFactory
        let defaultIOFactory = defaultIOFactory
        let nativeDevices = userAgentDevices
        let agent = agent
        _ = agent.performAudioSelection { revision in
            do {
                let devices = try devicesFactory.make()
                let defaultIO = try defaultIOFactory.make()
                guard agent.isAudioSelectionCurrent(revision) else { return PJ_ECANCELLED }
                let soundIO = preferences.resolve(devices: devices, defaultIO: defaultIO)
                let map = SystemToUserAgentAudioDeviceMap(systemDevices: devices.all, userAgentDevices: try nativeDevices())
                guard agent.isAudioSelectionCurrent(revision) else { return PJ_ECANCELLED }
                return agent.setSoundInputDevice(map.userAgentDevice(for: soundIO.input).identifier,
                    soundOutputDevice: map.userAgentDevice(for: soundIO.output).identifier) ? 0 : PJ_EUNKNOWN
            } catch {
                if agent.isAudioSelectionCurrent(revision) { agent.reportAudioSelectionFailure() }
                return PJ_EUNKNOWN
            }
        }
    }
}

private struct AudioSelectionPreferences {
    let inputName: String?
    let inputUID: String?
    let outputName: String?
    let outputUID: String?

    @MainActor init(settings: KeyValueSettings) {
        inputName = settings.string(forKey: SettingsKeys.soundInput)
        inputUID = settings.string(forKey: SettingsKeys.soundInputUID)
        outputName = settings.string(forKey: SettingsKeys.soundOutput)
        outputUID = settings.string(forKey: SettingsKeys.soundOutputUID)
    }

    func resolve(devices: SystemAudioDevices, defaultIO: SystemSoundIO) -> Domain.SoundIO {
        let fallback = Domain.PreferredSoundIO(devices: devices.all, defaultIO: defaultIO)
        let input = device(name: inputName, uid: inputUID, byName: devices.inputDevice(named:), byUID: devices.inputDevice(uniqueIdentifier:))
        let output = device(name: outputName, uid: outputUID, byName: devices.outputDevice(named:), byUID: devices.outputDevice(uniqueIdentifier:))
        return Domain.SimpleSoundIO(input: input.isNil ? fallback.input : input,
            output: output.isNil ? fallback.output : output, ringtoneOutput: fallback.ringtoneOutput)
    }

    private func device(name: String?, uid: String?, byName: (String) -> SystemAudioDevice,
                        byUID: (String) -> SystemAudioDevice) -> SystemAudioDevice {
        if let uid, !uid.isEmpty { return byUID(uid) }
        if let name { return byName(name) }
        return NullSystemAudioDevice()
    }
}
