#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Dispatch
import MacmojiCore

@MainActor
final class ClipboardHistoryController: ObservableObject {
    static let shared = ClipboardHistoryController()

    @Published private(set) var isShowing = false

    let model: ClipboardHistoryModel
    private let settings = AppSettings.shared
    private let store: ClipboardHistoryStore
    private let monitor = ClipboardMonitor()
    private let inserter = Inserter()
    private let captureQueue = DispatchQueue(
        label: "com.trevorgerald.macmoji.clipboard-capture",
        qos: .utility
    )
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var pendingPasteID: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    private lazy var panel: SearchableListPanel = {
        let panel = SearchableListPanel()
        panel.setRootView(ClipboardHistoryView(
            model: self.model,
            onPaste: { [weak self] in self?.pasteSelected() },
            onCopy: { [weak self] in self?.copySelected() }
        ))
        panel.handleKeyEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false }
        }
        panel.onHide = { [weak self] in
            MainActor.assumeIsolated { self?.isShowing = false }
        }
        return panel
    }()

    private init() {
        let storage = JSONFileClipboardHistoryStorage(
            baseURL: JSONFileClipboardHistoryStorage.defaultBaseURL()
        )
        let historyStore = ClipboardHistoryStore(
            storage: storage,
            configuration: ClipboardHistoryConfiguration(
                retention: AppSettings.shared.clipboardRetention,
                maximumUnpinnedEntries: 1_000
            )
        )
        store = historyStore
        model = ClipboardHistoryModel(store: historyStore)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.isCaptureEnabled = { [weak self] in
            guard let self else { return false }
            return self.settings.clipboardHistoryEnabled
                && !self.settings.clipboardHistoryPaused
                && self.settings.onboardingCompleted
        }
        monitor.excludedBundleIdentifiers = { [weak self] in
            self?.settings.clipboardExcludedApps ?? []
        }
        monitor.onCapture = { [weak self] captured, source in
            self?.record(captured, source: source)
        }
        monitor.start()
        synchronizeSettings()

        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.synchronizeSettings() }
        }.store(in: &cancellables)
    }

    func showHistory(
        previousApplication: NSRunningApplication? = nil,
        focusedElement: AXUIElement? = nil
    ) {
        guard settings.clipboardHistoryEnabled else { return }
        pendingPasteID = nil
        let candidate = previousApplication ?? NSWorkspace.shared.frontmostApplication
        if let candidate,
           !candidate.isTerminated,
           candidate.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            self.previousApplication = candidate
            previousFocusedElement = focusedElement ?? AXHelpers.focusedElement()
        } else {
            self.previousApplication = nil
            previousFocusedElement = nil
        }
        model.reset()
        isShowing = true
        panel.showOnActiveScreen()
    }

    func togglePaused() {
        settings.clipboardHistoryPaused.toggle()
    }

    func ignorePasteboardChange(_ changeCount: Int) {
        monitor.ignore(changeCount: changeCount)
    }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "All unpinned clipboard items will be deleted. Pinned items are kept."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearUnpinned()
        model.refresh()
    }

    func flush() {
        monitor.capturePendingChange()
        captureQueue.sync {}
        store.flush()
    }

    private func synchronizeSettings() {
        store.updateConfiguration(ClipboardHistoryConfiguration(
            retention: settings.clipboardRetention,
            maximumUnpinnedEntries: 1_000
        ))
        model.refresh()
    }

    private func record(_ captured: ClipboardCaptureContent, source: ClipboardSource) {
        captureQueue.async { [store] in
            guard let prepared = ClipboardImageProcessor.prepare(captured),
                  store.record(prepared, source: source) != nil else { return }
            store.flush()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.model.refresh() }
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)

        switch keyCode {
        case kVK_UpArrow:
            model.move(-1)
            return true
        case kVK_DownArrow:
            model.move(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if command { copySelected() } else { pasteSelected() }
            return true
        case kVK_Escape:
            closeAndRestoreFocus()
            return true
        case kVK_ANSI_P where command:
            model.togglePin()
            return true
        case kVK_Delete, kVK_ForwardDelete:
            guard command else { return false }
            model.deleteSelected()
            return true
        default:
            return false
        }
    }

    private func pasteSelected() {
        guard let application = previousApplication, !application.isTerminated else {
            NSSound.beep()
            return
        }
        guard let item = model.selected, writeToPasteboard(item) else { return }
        let operationID = UUID()
        pendingPasteID = operationID
        let expectedChangeCount = NSPasteboard.general.changeCount
        panel.hide()
        guard application.activate() else {
            pendingPasteID = nil
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pasteWhenFrontmost(
                application,
                expectedChangeCount: expectedChangeCount,
                operationID: operationID,
                attemptsRemaining: 20
            )
        }
    }

    private func copySelected() {
        pendingPasteID = nil
        guard let item = model.selected, writeToPasteboard(item) else { return }
        closeAndRestoreFocus()
    }

    private func closeAndRestoreFocus() {
        pendingPasteID = nil
        let application = previousApplication
        panel.hide()
        if let application, !application.isTerminated {
            application.activate()
        }
    }

    private func pasteWhenFrontmost(
        _ application: NSRunningApplication,
        expectedChangeCount: Int,
        operationID: UUID,
        attemptsRemaining: Int
    ) {
        guard pendingPasteID == operationID,
              NSPasteboard.general.changeCount == expectedChangeCount else {
            pendingPasteID = nil
            return
        }
        guard !application.isTerminated else {
            pendingPasteID = nil
            NSSound.beep()
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier {
            if let previousFocusedElement {
                guard AXUIElementSetAttributeValue(
                    previousFocusedElement,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                ) == .success else {
                    pendingPasteID = nil
                    NSSound.beep()
                    return
                }
            }
            pendingPasteID = nil
            inserter.pasteCurrentClipboard()
            return
        }
        guard attemptsRemaining > 0 else {
            // The item remains copied, but do not risk pasting into the wrong process.
            pendingPasteID = nil
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pasteWhenFrontmost(
                application,
                expectedChangeCount: expectedChangeCount,
                operationID: operationID,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        let pasteboard = NSPasteboard.general
        let imageData: Data?
        if case .image(let image) = item.content {
            guard let data = store.blobData(named: image.blobName) else { return false }
            imageData = data
        } else {
            imageData = nil
        }
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        let succeeded: Bool

        switch item.content {
        case .text(let value), .color(let value):
            succeeded = pasteboard.setString(value, forType: .string)

        case .link(let value):
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(value, forType: .URL)
            pasteboardItem.setString(value, forType: .string)
            succeeded = pasteboard.writeObjects([pasteboardItem])

        case .files(let paths):
            let urls = paths.map { NSURL(fileURLWithPath: $0) }
            succeeded = pasteboard.writeObjects(urls)

        case .image(let image):
            if let imageData {
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setData(
                    imageData,
                    forType: image.format == .png ? .png : .tiff
                )
                succeeded = pasteboard.writeObjects([pasteboardItem])
            } else {
                succeeded = false
            }
        }

        if !succeeded { restore(saved, to: pasteboard) }
        monitor.ignore(changeCount: pasteboard.changeCount)
        return succeeded
    }

    private typealias PasteboardSnapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private func snapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    private func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
#endif
