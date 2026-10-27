import Cocoa
import CryptoKit
import Darwin
import XCTest
@testable import Telephone

private final class RecordingHistoryActionEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}

@MainActor
final class RecordingHistoryActionsTests: XCTestCase {
    private let firstURL = URL(fileURLWithPath: "/synthetic/first.ogg")

    func testMenuAndValidationUseOnlyCachedSnapshots() {
        let events = RecordingHistoryActionEvents()
        let actions = RecordingHistoryActions(attachments: { _ in [self.attachment()] },
            persist: { _ in events.add("persist") }, resolve: { _ in events.add("resolve"); return (self.firstURL, false) },
            start: { _ in events.add("start"); return true }, stop: { _ in events.add("stop") },
            verify: { _, _ in events.add("verify") }, workspace: { _, _, _ in events.add("workspace") },
            presentError: { _ in events.add("alert") })
        for _ in 0..<1000 {
            let menu = actions.menu(forCallIdentifier: "call-A")
            XCTAssertTrue(actions.validateMenuItem(item("Play in Default App", in: menu)!))
        }
        XCTAssertTrue(events.all.isEmpty)
        XCTAssertEqual(actions.pendingActionCount, 0)
    }

    func testLegacyNilIdentifierHasNoFilenameInference() {
        var reads = 0
        let actions = RecordingHistoryActions(attachments: { _ in reads += 1; return [self.attachment()] })
        let menu = actions.menu(forCallIdentifier: nil)
        XCTAssertEqual(menu.items.first?.title, "No linked recordings for this call")
        XCTAssertEqual(reads, 0)
        XCTAssertNil(item("Play in Default App", in: menu))
    }

    func testMultipleSegmentsHaveIndividualSubmenusAndCapturedIdentity() throws {
        let actions = RecordingHistoryActions(attachments: { _ in [self.attachment(), self.attachment(segment: "segment-B")] })
        let menu = actions.menu(forCallIdentifier: "call-A")
        XCTAssertEqual(menu.items.prefix(2).compactMap(\.submenu).count, 2)
        let first = try XCTUnwrap(item("Play in Default App", in: menu.items[0].submenu!))
        let second = try XCTUnwrap(item("Reveal in Finder", in: menu.items[1].submenu!))
        XCTAssertEqual((first.representedObject as? NSDictionary)?["segmentIdentifier"] as? String, "segment-A")
        XCTAssertEqual((second.representedObject as? NSDictionary)?["segmentIdentifier"] as? String, "segment-B")
        XCTAssertEqual((second.representedObject as? NSDictionary)?["callIdentifier"] as? String, "call-A")
    }

    func testNonavailableStatesAreTruthfulAndUnplayable() throws {
        for (state, title) in [("capturing", "Recording in progress"), ("finalising", "Saving recording…"), ("failed", "Recording needs recovery"), ("unknown", "Recording details unavailable")] {
            let actions = RecordingHistoryActions(attachments: { _ in [self.attachment(state: state)] })
            let menu = actions.menu(forCallIdentifier: "call-A")
            XCTAssertEqual(menu.items.first?.title, title)
            XCTAssertFalse(try XCTUnwrap(item("Play in Default App", in: menu)).isEnabled)
            XCTAssertFalse(try XCTUnwrap(item("Reveal in Finder", in: menu)).isEnabled)
        }
        for (flag, title) in [("discarded", "Recording discarded"), ("startFailed", "Recording did not start")] {
            let value = attachment(state: "failed").mutableCopy() as! NSMutableDictionary
            value[flag] = true
            let actions = RecordingHistoryActions(attachments: { _ in [value] })
            XCTAssertEqual(actions.menu(forCallIdentifier: "call-A").items.first?.title, title)
        }
    }

    func testUnreadableCatalogueRetainsCachedAttachmentsAndShowsError() throws {
        let error = NSError(domain: "Synthetic", code: 5, userInfo: [NSLocalizedDescriptionKey: "Catalogue unavailable"])
        let actions = RecordingHistoryActions(attachments: { _ in [self.attachment()] }, catalogueError: { error })
        let menu = actions.menu(forCallIdentifier: "call-A")
        XCTAssertTrue(try XCTUnwrap(item("Play in Default App", in: menu)).isEnabled)
        XCTAssertEqual(menu.items.first { $0.title == "Recording catalogue unavailable" }?.toolTip, "Catalogue unavailable")
        let empty = RecordingHistoryActions(attachments: { _ in [] }, catalogueError: { error }, hasLoaded: { false })
        XCTAssertEqual(empty.menu(forCallIdentifier: "call-A").items.first?.title, "Recording catalogue unavailable")
        let loading = RecordingHistoryActions(attachments: { _ in [] }, hasLoaded: { false })
        XCTAssertEqual(loading.menu(forCallIdentifier: "call-A").items.first?.title, "Loading recording details…")
    }

    func testPlayOwnsSuccessfulScopeUntilWorkspaceCompletionAndDrainsOnce() async throws {
        let events = RecordingHistoryActionEvents()
        let called = expectation(description: "workspace")
        var completion: (@Sendable (Error?) -> Void)?
        let actions = makeActions(events: events, workspace: { url, reveal, done in
            XCTAssertEqual(url, self.firstURL); XCTAssertFalse(reveal)
            completion = done; called.fulfill()
        })
        let play = try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A")))
        invoke(play)
        invoke(play) // The same segment cannot acquire a second scope.
        await fulfillment(of: [called], timeout: 3)
        XCTAssertEqual(events.all, ["resolve", "start", "verify"])
        XCTAssertEqual(actions.pendingActionCount, 1)
        completion?(nil)
        completion?(nil) // A duplicate external completion cannot release twice.
        await drained(actions)
        XCTAssertEqual(events.all, ["resolve", "start", "verify", "stop"])
        XCTAssertEqual(actions.pendingActionCount, 0)
    }

    func testRevealKeepsExactResolvedOGGMP3AndWAVPath() async throws {
        for ext in ["ogg", "mp3", "wav"] {
            let moved = URL(fileURLWithPath: "/synthetic/moved/location.\(ext)")
            let events = RecordingHistoryActionEvents()
            let called = expectation(description: ext)
            let actions = makeActions(events: events, resolved: moved, workspace: { url, reveal, completion in
                XCTAssertEqual(url, moved); XCTAssertTrue(reveal)
                completion(nil); called.fulfill()
            })
            invoke(try XCTUnwrap(item("Reveal in Finder", in: actions.menu(forCallIdentifier: "call-A"))))
            await fulfillment(of: [called], timeout: 3)
            await drained(actions)
            XCTAssertEqual(events.all.last, "stop")
        }
    }

    func testFalseScopeResultUsesAccessibleFileWithoutUnbalancedStop() async throws {
        let events = RecordingHistoryActionEvents()
        let actions = makeActions(events: events, granted: false, workspace: { _, _, completion in completion(nil) })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await drained(actions)
        XCTAssertEqual(events.all, ["resolve", "start", "verify"])
    }

    func testStaleBookmarkIsVerifiedAndDurablyRefreshedBeforeOpen() async throws {
        let events = RecordingHistoryActionEvents()
        let moved = URL(fileURLWithPath: "/synthetic/renamed.ogg")
        let actions = RecordingHistoryActions(attachments: { _ in [self.attachment()] },
            persist: { value in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(value["outputBookmark"] as? Data, Data([8]))
                XCTAssertEqual(value["destination"] as? String, moved.path)
                events.add("persist")
            }, resolve: { _ in XCTAssertFalse(Thread.isMainThread); events.add("resolve"); return (moved, true) },
            bookmark: { _ in events.add("bookmark"); return Data([8]) },
            start: { _ in events.add("start"); return true }, stop: { _ in events.add("stop") },
            verify: { _, _ in XCTAssertFalse(Thread.isMainThread); events.add("verify") },
            workspace: { url, _, done in XCTAssertEqual(url, moved); events.add("workspace"); done(nil) },
            presentError: { _ in XCTFail("Unexpected alert") })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await drained(actions)
        XCTAssertEqual(events.all, ["resolve", "start", "verify", "bookmark", "persist", "workspace", "stop"])
    }

    func testStaleBookmarkPersistenceFailureStopsScopeAndDoesNotOpen() async throws {
        let events = RecordingHistoryActionEvents()
        let alert = expectation(description: "error")
        let actions = RecordingHistoryActions(attachments: { _ in [self.attachment()] },
            persist: { _ in events.add("persist"); throw NSError(domain: "Synthetic write", code: 1) },
            resolve: { _ in (URL(fileURLWithPath: "/synthetic/moved.ogg"), true) }, bookmark: { _ in Data([8]) },
            start: { _ in events.add("start"); return true }, stop: { _ in events.add("stop") },
            verify: { _, _ in events.add("verify") }, workspace: { _, _, _ in XCTFail("Must not open before durable repair") },
            presentError: { _ in XCTAssertTrue(Thread.isMainThread); alert.fulfill() })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await drained(actions)
        await fulfillment(of: [alert], timeout: 3)
        XCTAssertEqual(events.all, ["start", "verify", "persist", "stop"])
    }

    func testUnsupportedPlaybackReportsNativeErrorAndReleasesScope() async throws {
        let events = RecordingHistoryActionEvents()
        var message: String?
        let actions = makeActions(events: events, workspace: { _, _, completion in
            completion(NSError(domain: "Synthetic player", code: 5, userInfo: [NSLocalizedDescriptionKey: "No default app supports this file"]))
        }, error: { message = $0.localizedDescription })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await drained(actions)
        XCTAssertEqual(message, "No default app supports this file")
        XCTAssertEqual(events.all.last, "stop")
    }

    func testQuitSuppressesLateAlertButReleasesWorkspaceScopeBeforeDrain() async throws {
        let events = RecordingHistoryActionEvents()
        let called = expectation(description: "workspace")
        var completion: (@Sendable (Error?) -> Void)?
        let actions = makeActions(events: events, workspace: { _, _, done in completion = done; called.fulfill() }, error: { _ in XCTFail("Quit must suppress late alerts") })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await fulfillment(of: [called], timeout: 3)
        actions.actionsEnabled = false
        XCTAssertFalse(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))).isEnabled)
        XCTAssertEqual(actions.pendingActionCount, 1)
        completion?(NSError(domain: "Synthetic", code: 9))
        await drained(actions)
        XCTAssertEqual(events.all.last, "stop")
        XCTAssertEqual(actions.pendingActionCount, 0)
    }

    func testDeletedAndReplacedFilesAreRejectedByActualIdentityVerifier() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jps-history-action-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("synthetic.wav")
        let bytes = Data("synthetic recording".utf8)
        try bytes.write(to: file)
        let identity = try outputIdentity(file, bytes: bytes)
        for replacement in [false, true] {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            if replacement { try Data("different recording".utf8).write(to: file) }
            let attachment = self.attachment().mutableCopy() as! NSMutableDictionary
            attachment["outputIdentity"] = identity
            let events = RecordingHistoryActionEvents()
            var message: String?
            let actions = RecordingHistoryActions(attachments: { _ in [attachment] }, resolve: { _ in (file, false) },
                start: { _ in events.add("start"); return true }, stop: { _ in events.add("stop") },
                workspace: { _, _, _ in XCTFail("Missing/replaced file must not open") }, presentError: { message = $0.localizedDescription })
            invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
            await drained(actions)
            XCTAssertNotNil(message)
            XCTAssertEqual(events.all, ["start", "stop"])
            let menu = actions.menu(forCallIdentifier: "call-A")
            XCTAssertEqual(menu.items.first?.title, "Recording file unavailable")
            XCTAssertFalse(try XCTUnwrap(item("Play in Default App", in: menu)).isEnabled)
        }
    }

    func testChangedContentsWithSameInodeAndSizeAreRejectedByHash() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("jps-history-hash-\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = Data("original".utf8)
        try bytes.write(to: file)
        let identity = try outputIdentity(file, bytes: bytes)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("modified".utf8))
        try writer.close()
        let attachment = self.attachment().mutableCopy() as! NSMutableDictionary
        attachment["outputIdentity"] = identity
        var message: String?
        let actions = RecordingHistoryActions(attachments: { _ in [attachment] }, resolve: { _ in (file, false) },
            start: { _ in false }, stop: { _ in XCTFail("No successful scope") },
            workspace: { _, _, _ in XCTFail("Changed contents must not open") }, presentError: { message = $0.localizedDescription })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await drained(actions)
        XCTAssertTrue(message?.contains("changed") == true)
    }

    func testActualVerifierAcceptsSameResourceMovedToBookmarkResolvedPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jps-history-moved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("original.mp3"), moved = root.appendingPathComponent("renamed.mp3")
        let bytes = Data("synthetic mp3 fixture".utf8)
        try bytes.write(to: old)
        let identity = try outputIdentity(old, bytes: bytes)
        try FileManager.default.moveItem(at: old, to: moved)
        let attachment = self.attachment().mutableCopy() as! NSMutableDictionary
        attachment["outputIdentity"] = identity
        var opened: URL?
        let actions = RecordingHistoryActions(attachments: { _ in [attachment] }, resolve: { _ in (moved, false) },
            start: { _ in false }, stop: { _ in XCTFail("No successful scope") },
            workspace: { url, _, completion in opened = url; completion(nil) }, presentError: { _ in XCTFail("Same exact resource must remain usable") })
        invoke(try XCTUnwrap(item("Play in Default App", in: actions.menu(forCallIdentifier: "call-A"))))
        await drained(actions)
        XCTAssertEqual(opened, moved)
    }

    func testAdmittedActionRetainsHelperUntilItsScopeHasBeenReleased() async throws {
        let events = RecordingHistoryActionEvents()
        let called = expectation(description: "workspace")
        var completion: (@Sendable (Error?) -> Void)?
        var actions: RecordingHistoryActions? = makeActions(events: events, workspace: { _, _, done in
            completion = done; called.fulfill()
        })
        weak var retained = actions
        invoke(try XCTUnwrap(item("Play in Default App", in: actions!.menu(forCallIdentifier: "call-A"))))
        let finished = expectation(description: "scope released and drained")
        actions!.waitForPendingActions { finished.fulfill() }
        actions = nil
        await fulfillment(of: [called], timeout: 3)
        XCTAssertNotNil(retained, "Admitted action owns its helper through workspace completion")
        XCTAssertFalse(events.all.contains("stop"))
        completion?(nil)
        // The callback itself is an external owner while it is stored here.
        completion = nil
        await fulfillment(of: [finished], timeout: 3)
        for _ in 0..<100 where retained != nil { await Task.yield() }
        XCTAssertEqual(events.all.last, "stop")
        XCTAssertNil(retained, "Completion must release the operation's helper ownership")
    }

    func testNativeErrorAlertFitsAndRetainsFeedbackInLightAndDark() throws {
        for (name, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let alert = RecordingHistoryActions.makeErrorAlert(NSError(domain: "Synthetic player", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "No default application could open this saved OGG recording. You can reveal the exact file in Finder and choose a compatible player."]))
            XCTAssertEqual(alert.messageText, "Recording unavailable")
            XCTAssertEqual(alert.buttons.map(\.title), ["OK"])
            let window = alert.window
            window.appearance = NSAppearance(named: name)
            // beginSheet/runModal normally performs this public AppKit layout.
            // A detached alert's placeholder window is not rendered acceptance.
            alert.layout()
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            defer { window.close() }
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            view.displayIfNeeded()
            func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
            let visible = descendants(view).filter { !$0.isHiddenOrHasHiddenAncestor && !$0.bounds.isEmpty }
            let buttons = visible.compactMap { $0 as? NSButton }
            XCTAssertEqual(buttons.map(\.title), ["OK"], "Only the real OK button may be visible after native layout")
            let body = try XCTUnwrap(visible.compactMap { $0 as? NSTextField }.first { $0.stringValue == alert.informativeText })
            let required = body.attributedStringValue.boundingRect(
                with: NSSize(width: body.bounds.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            XCTAssertLessThanOrEqual(ceil(required.height), ceil(body.bounds.height) + 1, "The complete feedback must fit its native body field")
            for element in [body] + buttons {
                XCTAssertTrue(view.bounds.contains(element.convert(element.bounds, to: view)))
            }
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let cached = try XCTUnwrap(NSImage(data: try XCTUnwrap(bitmap.tiffRepresentation)))
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                view.bounds.fill()
                cached.draw(in: view.bounds)
            }
            image.unlockFocus()
            let attachment = XCTAttachment(image: image)
            attachment.name = "recording69-error-\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(view.bounds.width, 200)
            XCTAssertGreaterThan(view.bounds.height, 100)
        }
    }

    private func makeActions(events: RecordingHistoryActionEvents, resolved: URL? = nil, granted: Bool = true,
                             workspace: @escaping RecordingHistoryActions.WorkspaceAction,
                             error: @escaping (Error) -> Void = { _ in XCTFail("Unexpected alert") }) -> RecordingHistoryActions {
        let url = resolved ?? firstURL
        return RecordingHistoryActions(attachments: { _ in [self.attachment()] },
            resolve: { _ in XCTAssertFalse(Thread.isMainThread); events.add("resolve"); return (url, false) },
            start: { _ in events.add("start"); return granted }, stop: { _ in events.add("stop") },
            verify: { _, _ in XCTAssertFalse(Thread.isMainThread); events.add("verify") }, workspace: workspace, presentError: error)
    }

    private func attachment(segment: String = "segment-A", state: String = "available") -> NSDictionary {
        ["callIdentifier": "call-A", "segmentIdentifier": segment, "state": state,
         "created": Date(timeIntervalSince1970: 1000), "destination": firstURL.path,
         "outputBookmark": Data([1]), "outputIdentity": ["dev": "1", "ino": "2", "size": 1, "sha256": String(repeating: "a", count: 64)]]
    }

    private func item(_ title: String, in menu: NSMenu) -> NSMenuItem? { menu.items.first { $0.title == title } }
    private func invoke(_ item: NSMenuItem) { XCTAssertTrue(NSApp.sendAction(item.action!, to: item.target, from: item)) }
    private func drained(_ actions: RecordingHistoryActions) async {
        await withCheckedContinuation { continuation in actions.waitForPendingActions { continuation.resume() } }
    }
    private func outputIdentity(_ url: URL, bytes: Data) throws -> NSDictionary {
        var value = stat()
        XCTAssertEqual(lstat(url.path, &value), 0)
        return ["dev": String(value.st_dev), "ino": String(value.st_ino), "size": NSNumber(value: value.st_size),
                "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
    }
}

@MainActor
final class RecordingHistoryMenuSelectionTests: XCTestCase {
    func testCapturedActionSurvivesFilteredRowsPrependAndAnotherSelection() async throws {
        let first: NSDictionary = ["callIdentifier": "recording-A", "segmentIdentifier": "segment-A", "state": "available",
            "destination": "/synthetic/first.wav", "outputBookmark": Data([1]), "outputIdentity": ["synthetic": true]]
        let second: NSDictionary = ["callIdentifier": "recording-B", "segmentIdentifier": "segment-B", "state": "available",
            "destination": "/synthetic/second.wav", "outputBookmark": Data([2]), "outputIdentity": ["synthetic": true]]
        let events = RecordingHistoryActionEvents()
        var opened: URL?
        let actions = RecordingHistoryActions(attachments: { id in id == "recording-A" ? [first] : id == "recording-B" ? [second] : [] },
            resolve: { data in
                events.add("resolved-\(data.first!)")
                return (URL(fileURLWithPath: data == Data([1]) ? "/synthetic/first.wav" : "/synthetic/second.wav"), false)
            }, start: { _ in false }, stop: { _ in XCTFail("No successful scope") }, verify: { _, _ in },
            workspace: { url, _, done in opened = url; done(nil) }, presentError: { _ in XCTFail("Unexpected error") })
        let controller = CallHistoryViewController()
        _ = controller.view
        controller.recordingHistoryActions = actions
        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        controller.show([record("row-A", call: "recording-A"), record("row-B", call: "recording-B")])
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let firstMenu = try XCTUnwrap(controller.actionsMenu.items.first { $0.title == "Recording" }?.submenu)
        let captured = try XCTUnwrap(firstMenu.items.first { $0.title == "Play in Default App" })
        controller.show([record("new", call: nil), record("row-A", call: "recording-A"), record("row-B", call: "recording-B")])
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let secondMenu = try XCTUnwrap(controller.actionsMenu.items.first { $0.title == "Recording" }?.submenu)
        XCTAssertEqual((secondMenu.items.first { $0.title == "Play in Default App" }?.representedObject as? NSDictionary)?["callIdentifier"] as? String, "recording-B")
        let search = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSSearchField }.first)
        search.stringValue = "new"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertEqual(table.selectedRow, -1)
        XCTAssertTrue(NSApp.sendAction(captured.action!, to: captured.target, from: captured))
        await withCheckedContinuation { continuation in actions.waitForPendingActions { continuation.resume() } }
        XCTAssertEqual(events.all, ["resolved-1"])
        XCTAssertEqual(opened?.path, "/synthetic/first.wav")
    }

    func testAccountMoreMenuCopiesSelectedRecordingActionsAlongsideClearHistory() throws {
        let (history, actions) = try historyWithSelectedRecording()
        // The real AccountViewController getter needs only its history child and
        // hidden purchase button. Bypass account/purchase factories entirely.
        let type = try XCTUnwrap(NSClassFromString("AccountViewController") as? NSViewController.Type)
        let account = type.init(nibName: nil, bundle: nil)
        let purchase = NSButton(title: "Synthetic purchase", target: nil, action: nil)
        purchase.isHidden = true
        account.setValue(history, forKey: "callHistoryViewController")
        account.setValue(purchase, forKey: "showMoreButton")
        XCTAssertFalse(account.isViewLoaded)
        let menu = try XCTUnwrap(account.perform(NSSelectorFromString("callHistoryActionsMenu"))?.takeUnretainedValue() as? NSMenu)
        try assertRecordingActionsReachMoreMenu(menu, actions: actions)
        XCTAssertFalse(account.isViewLoaded, "Constructing More must not start account or purchase work")
    }

    func testSharedDiallerMoreMenuCopiesSelectedRecordingActionsAlongsideExistingActions() throws {
        let (history, actions) = try historyWithSelectedRecording()
        // Select the existing native window-only construction seam. This invokes
        // the production More getter without creating a SIP account or factory.
        let type = try XCTUnwrap(NSClassFromString("SharedDialerController") as? NSWindowController.Type)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 368, height: 104),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let shared = type.init(window: window)
        shared.setValue(history, forKey: "history")
        let menu = try XCTUnwrap(shared.perform(NSSelectorFromString("moreActionsMenu"))?.takeUnretainedValue() as? NSMenu)
        try assertRecordingActionsReachMoreMenu(menu, actions: actions)
        XCTAssertNotNil(menu.items.first { $0.title == "Guided routes…" })
        XCTAssertEqual(window.contentView?.bounds.size, NSSize(width: 368, height: 104))
    }

    private func historyWithSelectedRecording() throws -> (CallHistoryViewController, RecordingHistoryActions) {
        let attachment: NSDictionary = ["callIdentifier": "recording-more", "segmentIdentifier": "segment-more", "state": "available",
            "destination": "/synthetic/more.wav", "outputBookmark": Data([3]), "outputIdentity": ["synthetic": true]]
        let actions = RecordingHistoryActions(attachments: { $0 == "recording-more" ? [attachment] : [] },
            resolve: { _ in XCTFail("Menu construction must not resolve bookmarks"); return (URL(fileURLWithPath: "/synthetic/more.wav"), false) },
            start: { _ in XCTFail("Menu construction must not acquire grants"); return false },
            stop: { _ in XCTFail("Menu construction acquired no grants") },
            verify: { _, _ in XCTFail("Menu construction must not inspect audio") },
            workspace: { _, _, _ in XCTFail("Menu construction must not launch anything") }, presentError: { _ in XCTFail("No menu-time alerts") })
        let controller = CallHistoryViewController()
        _ = controller.view
        controller.recordingHistoryActions = actions
        controller.show([record("more-row", call: "recording-more")])
        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        return (controller, actions)
    }

    private func assertRecordingActionsReachMoreMenu(_ menu: NSMenu, actions: RecordingHistoryActions) throws {
        XCTAssertNotNil(menu.items.first { $0.action == NSSelectorFromString("deleteAll:") })
        let recording = try XCTUnwrap(menu.items.first { $0.tag == 690 })
        XCTAssertEqual(recording.title, "Recording")
        let submenu = try XCTUnwrap(recording.submenu)
        for title in ["Play in Default App", "Reveal in Finder"] {
            let item = try XCTUnwrap(submenu.items.first { $0.title == title })
            XCTAssertTrue(item.target as? RecordingHistoryActions === actions)
            XCTAssertTrue(actions.validateMenuItem(item))
            let identity = try XCTUnwrap(item.representedObject as? NSDictionary)
            XCTAssertEqual(identity["callIdentifier"] as? String, "recording-more")
            XCTAssertEqual(identity["segmentIdentifier"] as? String, "segment-more")
        }
    }

    private func record(_ id: String, call: String?) -> PresentationCallHistoryRecord {
        PresentationCallHistoryRecord(identifier: id, contact: PresentationContact(title: id, tooltip: "", label: "home", color: .labelColor, address: "synthetic"),
            date: "Today", duration: "0 sec", isIncoming: false, recordingCallIdentifier: call)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
