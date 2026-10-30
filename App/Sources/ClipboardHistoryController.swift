#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Combine
import Dispatch
import MacmojiCore

@MainActor
final class ClipboardHistoryController: ObservableObject {
    static let shared = ClipboardHistoryController()

    @Published private(set) var hotKeyError: String?
    @Published private(set) var isShowing = false

    let model: ClipboardHistoryModel
    private let settings = AppSettings.shared
    private let store: ClipboardHistoryStore
    private let monitor = ClipboardMonitor()
    private let globalHotKey = GlobalHotKey()
    private let inserter = Inserter()
    private let captureQueue = DispatchQueue(
        label: "com.trevorgerald.macmoji.clipboard-capture",
        qos: .utility
    )
    private var previousApplication: NSRunningApplication?
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

    func showHistory(previousApplication: NSRunningApplication? = nil) {
        guard settings.clipboardHistoryEnabled else { return }
        let candidate = previousApplication ?? NSWorkspace.shared.frontmostApplication
        if let candidate,
           !candidate.isTerminated,
           candidate.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            self.previousApplication = candidate
        } else {
            self.previousApplication = nil
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
        captureQueue.sync {}
        store.flush()
    }

    private func synchronizeSettings() {
        store.updateConfiguration(ClipboardHistoryConfiguration(
            retention: settings.clipboardRetention,
            maximumUnpinnedEntries: 1_000
        ))
        model.refresh()

        guard settings.clipboardHistoryEnabled, settings.clipboardHotKeyEnabled else {
            globalHotKey.unregister()
            hotKeyError = nil
            return
        }
        let configuration = ClipboardHotKey(
            key: settings.clipboardHotKeyKey,
            modifiers: settings.clipboardHotKeyModifiers
        )
        let registered = globalHotKey.register(configuration) { [weak self] in
            self?.showHistory()
        }
        hotKeyError = registered ? nil : "Could not register \(configuration.displayString). It may be in use."
    }

    private func record(_ captured: ClipboardCaptureContent, source: ClipboardSource) {
        captureQueue.async { [store] in
            guard store.record(captured, source: source) != nil else { return }
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
        case kVK_Delete, kVK_ForwardDelete where command:
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
        panel.hide()
        guard application.activate(options: [.activateIgnoringOtherApps]) else {
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [inserter] in
            inserter.pasteCurrentClipboard()
        }
    }

    private func copySelected() {
        guard let item = model.selected, writeToPasteboard(item) else { return }
        closeAndRestoreFocus()
    }

    private func closeAndRestoreFocus() {
        let application = previousApplication
        panel.hide()
        if let application, !application.isTerminated {
            application.activate(options: [.activateIgnoringOtherApps])
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
