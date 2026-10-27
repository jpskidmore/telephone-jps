// Recording attachments are selected by immutable call and segment identifiers.
// Menu construction/validation only use the catalogue's cached main snapshots.
import Cocoa
import CryptoKit
import Darwin

private struct RecordingHistoryActionKey: Hashable, Sendable {
    let call: String
    let segment: String

    init?(_ value: Any?) {
        guard let dict = value as? NSDictionary,
              let call = dict["callIdentifier"] as? String, !call.isEmpty,
              let segment = dict["segmentIdentifier"] as? String, !segment.isEmpty else { return nil }
        self.call = call
        self.segment = segment
    }

    var representedObject: NSDictionary {
        ["callIdentifier": call, "segmentIdentifier": segment]
    }
}

private final class RecordingHistoryAttachment: @unchecked Sendable {
    let value: NSDictionary
    init(_ value: NSDictionary) { self.value = value.copy() as! NSDictionary }
}

private final class RecordingHistoryActionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    func set(_ value: Bool) { lock.withLock { enabled = value } }
    var isEnabled: Bool { lock.withLock { enabled } }
    func take() -> Bool { lock.withLock { let value = enabled; enabled = false; return value } }
}

private struct RecordingHistoryPreparedFile: Sendable {
    let url: URL
    let granted: Bool
    let bookmarkRefreshed: Bool
}

// All resolver, file and persistence seams run on one utility queue. Neither
// constructing a history menu nor asking AppKit to validate one can reach them.
private final class RecordingHistoryActionWorker: @unchecked Sendable {
    let resolve: (Data) throws -> (url: URL, stale: Bool)
    let bookmark: (URL) throws -> Data
    let start: (URL) -> Bool
    let stop: (URL) -> Void
    let verify: (URL, NSDictionary) throws -> Void
    let persist: (NSDictionary) throws -> Void

    init(resolve: @escaping (Data) throws -> (url: URL, stale: Bool),
         bookmark: @escaping (URL) throws -> Data,
         start: @escaping (URL) -> Bool, stop: @escaping (URL) -> Void,
         verify: @escaping (URL, NSDictionary) throws -> Void,
         persist: @escaping (NSDictionary) throws -> Void) {
        self.resolve = resolve; self.bookmark = bookmark
        self.start = start; self.stop = stop; self.verify = verify; self.persist = persist
    }

    func prepare(_ attachment: RecordingHistoryAttachment) throws -> RecordingHistoryPreparedFile {
        guard attachment.value["state"] as? String == "available",
              let data = attachment.value["outputBookmark"] as? Data, !data.isEmpty,
              attachment.value["bookmarkIsDirectory"] as? Bool != true,
              let identity = attachment.value["outputIdentity"] as? NSDictionary else {
            throw recordingHistoryError("This recording does not have a saved, verifiable file reference. Open Recording Recovery for any retained tracks.")
        }
        let result = try resolve(data)
        guard result.url.isFileURL else { throw recordingHistoryError("The saved recording reference is not a local file.") }
        let granted = start(result.url)
        do {
            // A false scope result also occurs for an otherwise accessible
            // non-scoped file. Exact verification decides whether it is usable.
            try verify(result.url, identity)
            if result.stale {
                let updated = attachment.value.mutableCopy() as! NSMutableDictionary
                updated["outputBookmark"] = try bookmark(result.url)
                updated["destination"] = result.url.path
                try persist(updated)
            }
            return RecordingHistoryPreparedFile(url: result.url, granted: granted, bookmarkRefreshed: result.stale)
        } catch {
            if granted { stop(result.url) }
            throw error
        }
    }
}

private func recordingHistoryError(_ description: String, underlying: Error? = nil) -> NSError {
    var info: [String: Any] = [NSLocalizedDescriptionKey: description]
    if let underlying { info[NSUnderlyingErrorKey] = underlying }
    return NSError(domain: "RecordingHistoryActions", code: 1, userInfo: info)
}

// The bookmark can follow a renamed file, but a different file at its former
// path must never inherit the attachment. Hashing is streamed on the utility
// queue, with no-follow open and a second descriptor identity/length check.
private func verifyRecordingHistoryOutput(_ url: URL, _ identity: NSDictionary) throws {
    guard let device = identity["dev"] as? String,
          let inode = identity["ino"] as? String,
          let size = identity["size"] as? NSNumber,
          let expectedHash = identity["sha256"] as? String, expectedHash.count == 64 else {
        throw recordingHistoryError("The saved recording has incomplete file verification details.")
    }
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else {
        throw recordingHistoryError("The recording file is missing or cannot be accessed. Restore the original file or use Recording Recovery for retained tracks.",
                                    underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
    }
    defer { Darwin.close(fd) }
    var before = stat()
    guard fstat(fd, &before) == 0,
          before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          String(before.st_dev) == device, String(before.st_ino) == inode,
          before.st_size == size.int64Value else {
        throw recordingHistoryError("The saved location now refers to a different or changed file. This recording cannot be opened safely.")
    }
    var hash = SHA256()
    var bytes = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if count < 0 {
            if errno == EINTR { continue }
            throw recordingHistoryError("The recording could not be read.", underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        if count == 0 { break }
        hash.update(data: Data(bytes.prefix(count)))
    }
    var after = stat()
    guard fstat(fd, &after) == 0,
          before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size,
          before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
          before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
          hash.finalize().map({ String(format: "%02x", $0) }).joined() == expectedHash.lowercased() else {
        throw recordingHistoryError("The recording file has changed since it was saved. This recording cannot be opened safely.")
    }
}

@MainActor
@objc final class RecordingHistoryActions: NSObject, NSMenuItemValidation {
    typealias AttachmentProvider = (String) -> [NSDictionary]
    typealias WorkspaceAction = (URL, Bool, @escaping @Sendable (Error?) -> Void) -> Void
    typealias RefreshCompletion = @MainActor @Sendable (Bool) -> Void

    @objc var actionsEnabled = true {
        didSet { gate.set(actionsEnabled) }
    }
    @objc var pendingActionCount: Int { busy.count }
    private let attachments: AttachmentProvider
    private let catalogueError: () -> Error?
    private let catalogueHasLoaded: () -> Bool
    private let refresh: (@escaping RefreshCompletion) -> Void
    private let workspace: WorkspaceAction
    private let presentError: (Error) -> Void
    private let worker: RecordingHistoryActionWorker
    private let queue = DispatchQueue(label: "org.jps.Telephone.recording-history-actions", qos: .utility)
    private let drain = DispatchGroup()
    private let gate = RecordingHistoryActionGate()
    private var busy = Set<RecordingHistoryActionKey>()
    private var unavailable: [RecordingHistoryActionKey: String] = [:]

    @objc(initWithCatalogue:)
    convenience init(catalogue: AKRecordingCatalogue) {
        self.init(attachments: { catalogue.attachments(forCallIdentifier: $0).map { $0 as NSDictionary } },
                  catalogueError: { catalogue.error }, hasLoaded: { catalogue.hasLoaded },
                  refresh: { completion in catalogue.refresh { value in DispatchQueue.main.async { completion(value) } } },
                  persist: { _ = try catalogue.persistAttachment($0 as! [AnyHashable: Any]) })
    }

    // Internal seams let hosted tests exercise the actual native menu and
    // asynchronous ownership without opening a player, Finder or real grants.
    init(attachments: @escaping AttachmentProvider,
         catalogueError: @escaping () -> Error? = { nil }, hasLoaded: @escaping () -> Bool = { true },
         refresh: @escaping (@escaping RefreshCompletion) -> Void = { $0(true) },
         persist: @escaping (NSDictionary) throws -> Void = { _ in },
         resolve: @escaping (Data) throws -> (url: URL, stale: Bool) = { data in
             var stale = false
             let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
             return (url, stale)
         },
         bookmark: @escaping (URL) throws -> Data = { try $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) },
         start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
         verify: @escaping (URL, NSDictionary) throws -> Void = verifyRecordingHistoryOutput,
         workspace: @escaping WorkspaceAction = { url, reveal, completion in
             if reveal {
                 NSWorkspace.shared.activateFileViewerSelecting([url])
                 completion(nil)
             } else {
                 NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                     completion(error ?? (app == nil ? recordingHistoryError("No application could open this recording.") : nil))
                 }
             }
         },
         presentError: @escaping (Error) -> Void = { error in
             let alert = RecordingHistoryActions.makeErrorAlert(error)
             if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
             else { alert.runModal() }
         }) {
        self.attachments = attachments; self.catalogueError = catalogueError; self.catalogueHasLoaded = hasLoaded
        self.refresh = refresh; self.workspace = workspace; self.presentError = presentError
        worker = RecordingHistoryActionWorker(resolve: resolve, bookmark: bookmark, start: start, stop: stop, verify: verify, persist: persist)
        super.init()
    }

    static func makeErrorAlert(_ error: Error) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Recording unavailable"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        return alert
    }

    @objc(menuForCallIdentifier:)
    func menu(forCallIdentifier identifier: String?) -> NSMenu {
        let menu = NSMenu(title: "Recording")
        guard let identifier, !identifier.isEmpty else {
            menu.addItem(disabled("No linked recordings for this call"))
            return menu
        }
        let values = attachments(identifier).filter { $0["callIdentifier"] as? String == identifier }
        if values.isEmpty {
            menu.addItem(disabled(catalogueError() != nil ? "Recording catalogue unavailable" : catalogueHasLoaded() ? "No linked recordings for this call" : "Loading recording details…"))
        } else {
            for (index, attachment) in values.enumerated() {
                let segmentMenu = makeSegmentMenu(attachment)
                if values.count == 1 {
                    for item in segmentMenu.items {
                        segmentMenu.removeItem(item)
                        menu.addItem(item)
                    }
                } else {
                    let item = NSMenuItem(title: segmentTitle(attachment, index: index), action: nil, keyEquivalent: "")
                    item.submenu = segmentMenu
                    menu.addItem(item)
                }
            }
            if let error = catalogueError() {
                menu.addItem(.separator())
                let item = disabled("Recording catalogue unavailable")
                item.toolTip = error.localizedDescription
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Refresh Recording Details", action: #selector(refreshDetails(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = actionsEnabled
        menu.addItem(item)
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func segmentTitle(_ attachment: NSDictionary, index: Int) -> String {
        let created = attachment["created"] as? Date ?? attachment["date"] as? Date
        guard let created else { return "Recording \(index + 1)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateStyle = .short; formatter.timeStyle = .short
        return "Recording \(index + 1) — \(formatter.string(from: created))"
    }

    private func makeSegmentMenu(_ attachment: NSDictionary) -> NSMenu {
        let menu = NSMenu()
        guard let key = RecordingHistoryActionKey(attachment) else {
            menu.addItem(disabled("Recording details unavailable")); return menu
        }
        let state = attachment["state"] as? String ?? ""
        let title: String
        if busy.contains(key) { title = "Opening recording…" }
        else if unavailable[key] != nil { title = "Recording file unavailable" }
        else {
            switch state {
            case "capturing": title = "Recording in progress"
            case "finalising": title = "Saving recording…"
            case "failed":
                if attachment["startFailed"] as? Bool == true { title = "Recording did not start" }
                else if attachment["discarded"] as? Bool == true { title = "Recording discarded" }
                else { title = "Recording needs recovery" }
            case "available": title = "Saved recording"
            default: title = "Recording details unavailable"
            }
        }
        let status = disabled(title)
        status.toolTip = unavailable[key] ?? attachment["lastErrorDescription"] as? String ?? attachment["reason"] as? String
        menu.addItem(status)
        if let destination = attachment["destination"] as? String, !destination.isEmpty {
            let file = disabled(URL(fileURLWithPath: destination).lastPathComponent)
            file.toolTip = destination
            menu.addItem(file)
        }
        for (title, selector) in [("Play in Default App", #selector(play(_:))), ("Reveal in Finder", #selector(reveal(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; item.representedObject = key.representedObject
            item.isEnabled = canAct(on: key)
            menu.addItem(item)
        }
        return menu
    }

    private func attachment(for key: RecordingHistoryActionKey) -> NSDictionary? {
        attachments(key.call).first { $0["callIdentifier"] as? String == key.call && $0["segmentIdentifier"] as? String == key.segment }
    }

    private func canAct(on key: RecordingHistoryActionKey) -> Bool {
        guard actionsEnabled, !busy.contains(key), unavailable[key] == nil,
              let value = attachment(for: key), value["state"] as? String == "available",
              let bookmark = value["outputBookmark"] as? Data, !bookmark.isEmpty,
              value["bookmarkIsDirectory"] as? Bool != true, value["discarded"] as? Bool != true, value["startFailed"] as? Bool != true,
              value["outputIdentity"] is NSDictionary else { return false }
        return true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(refreshDetails(_:)) { return actionsEnabled }
        guard let key = RecordingHistoryActionKey(item.representedObject) else { return false }
        return canAct(on: key)
    }

    @objc private func refreshDetails(_ sender: NSMenuItem) {
        guard actionsEnabled else { return }
        refresh { [weak self] _ in self?.unavailable.removeAll() }
    }

    @objc private func play(_ sender: NSMenuItem) { perform(sender, reveal: false) }
    @objc private func reveal(_ sender: NSMenuItem) { perform(sender, reveal: true) }

    private func perform(_ sender: NSMenuItem, reveal: Bool) {
        guard let key = RecordingHistoryActionKey(sender.representedObject), canAct(on: key),
              let value = attachment(for: key) else { return }
        busy.insert(key)
        drain.enter()
        let snapshot = RecordingHistoryAttachment(value)
        let worker = worker, gate = gate, queue = queue
        queue.async { [self] in
            guard gate.isEnabled else {
                DispatchQueue.main.async { self.finish(key, error: nil, unavailable: false) }
                return
            }
            let result = Swift.Result<RecordingHistoryPreparedFile, Error>(catching: { try worker.prepare(snapshot) })
            DispatchQueue.main.async { [self] in
                switch result {
                case .failure(let error):
                    self.finish(key, error: error, unavailable: true)
                case .success(let file):
                    guard self.actionsEnabled, gate.isEnabled else {
                        queue.async {
                            if file.granted { worker.stop(file.url) }
                            DispatchQueue.main.async { self.finish(key, error: nil, unavailable: false) }
                        }
                        return
                    }
                    if file.bookmarkRefreshed { self.refresh { _ in } }
                    let completionGate = RecordingHistoryActionGate()
                    self.workspace(file.url, reveal) { [self] error in
                        guard completionGate.take() else { return }
                        queue.async {
                            if file.granted { worker.stop(file.url) }
                            DispatchQueue.main.async { self.finish(key, error: error, unavailable: false) }
                        }
                    }
                }
            }
        }
    }

    private func finish(_ key: RecordingHistoryActionKey, error: Error?, unavailable shouldMarkUnavailable: Bool) {
        guard busy.remove(key) != nil else { return }
        if let error {
            if shouldMarkUnavailable { unavailable[key] = error.localizedDescription }
            if actionsEnabled { presentError(error) }
        }
        drain.leave()
    }

    @objc(waitForPendingActionsWithCompletion:)
    func waitForPendingActions(completion: @escaping @Sendable () -> Void) {
        drain.notify(queue: .main, execute: completion)
    }
}
