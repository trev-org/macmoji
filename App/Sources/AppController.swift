#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Combine
import MacmojiCore

/// Wires the event tap, state machine, search, picker and inserter together.
/// Everything runs on the main thread (the tap's run loop source is on the main run loop).
@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var statusText = "Starting…"

    private let settings = AppSettings.shared
    private let permissions = PermissionManager()
    private let context = AppContext()
    private let inserter = Inserter()
    private let usage = UsageStore(fileURL: UsageStore.defaultFileURL())
    private var search: EmojiSearch?
    private var machine = TriggerStateMachine()
    private lazy var tap = KeyTap { [unowned self] type, event in self.handle(type: type, event: event) }
    private let model = PickerModel()
    private lazy var panel = PickerPanel(model: model)
    private var pickerShown = false
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        do {
            let store = try EmojiStore.bundled()
            search = EmojiSearch(store: store, usage: usage)
            machine = TriggerStateMachine(isExactName: { store.emoji(named: $0) != nil })
        } catch {
            statusText = "Could not load emoji data"
            NSLog("macmoji: failed to load emoji.json: \(error)")
            return
        }
        model.onChoose = { [unowned self] index in self.commit(index: index) }
        context.onAppChanged = { [unowned self] in self.resetTracking(); self.refreshStatus() }
        tap.onDisabled = { NSLog("macmoji: event tap was disabled by macOS; re-enabled") }
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }.store(in: &cancellables)

        if AXIsProcessTrusted() {
            startTap()
        } else {
            showOnboarding()
        }
        // Watch for the grant being revoked or (re)granted while running.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
        refreshStatus()
    }

    func showOnboarding() {
        permissions.showOnboarding { [weak self] in self?.startTap() }
    }

    private func startTap() {
        isTrusted = AXIsProcessTrusted()
        if !tap.start() { NSLog("macmoji: CGEvent.tapCreate failed") }
        refreshStatus()
    }

    private func checkTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        if trusted { startTap() } else { tap.stop(); resetTracking() }
        refreshStatus()
    }

    private func refreshStatus() {
        if !isTrusted { statusText = "Needs Accessibility permission" }
        else if !tap.isRunning { statusText = "Event tap not running (relaunch macmoji)" }
        else if !settings.enabled { statusText = "Paused" }
        else if settings.isBlocked(context.frontmostBundleID) { statusText = "Off in this app" }
        else { statusText = "Active — type :name" }
    }

    // MARK: Event handling (called from the tap; keep it fast)

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else {
            // Mouse click: clicks inside the picker choose a row; anything else ends tracking.
            if pickerShown && panel.frame.contains(NSEvent.mouseLocation) { return false }
            resetTracking()
            return false
        }

        guard settings.enabled, !settings.isBlocked(context.frontmostBundleID), !context.isSecureInputOn else {
            resetTracking()
            return false
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if pickerShown {
            switch keyCode {
            case kVK_UpArrow: model.move(-1); return true
            case kVK_DownArrow: model.move(1); return true
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
                commit(index: model.selection); return true
            case kVK_Escape:
                machine.cancel(); hidePicker(); return true
            default: break
            }
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            resetTracking()
            return false
        }

        switch keyCode {
        case kVK_Delete:
            apply(machine.handle(.backspace))
            return false
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End,
             kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Escape:
            resetTracking()
            return false
        default:
            break
        }

        let typed = event.typedString
        if typed.isEmpty {
            resetTracking()
            return false
        }
        for ch in typed {
            if ch == ":" && machine.state == .idle && context.focusedElementIsSecure() {
                resetTracking()
                return false
            }
            apply(machine.handle(.character(ch)))
        }
        return false
    }

    private func apply(_ action: TriggerStateMachine.Action) {
        switch action {
        case .none:
            break
        case .hide:
            hidePicker()
        case .show(let query):
            showPicker(query: query)
        case .autoReplace(let name, let deleteCount):
            hidePicker()
            guard let emoji = search?.store.emoji(named: name) else { return }
            machine.didCommit()
            usage.record(emoji.emoji)
            let text = emoji.rendered(tone: settings.skinTone)
            let strategy = currentStrategy()
            // The closing ':' is passing through right now; let it land before deleting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [inserter] in
                inserter.replace(deleteCount: deleteCount, with: text, strategy: strategy)
            }
        }
    }

    private func showPicker(query: String) {
        guard let search else { return }
        let results = search.search(query, limit: 8)
        guard !results.isEmpty else { hidePicker(); return }
        model.set(query: query, results: results, tone: settings.skinTone)
        if pickerShown {
            panel.resize(rowCount: results.count)
            return
        }
        pickerShown = true
        // The key that triggered this has not reached the target app yet; locate the caret
        // a moment later so the AX bounds include it, and outside the tap callback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, self.pickerShown else { return }
            let location = CaretLocator.locate()
            self.panel.show(rowCount: self.model.results.count, caret: location.rect)
            #if DEBUG
            NSLog("macmoji: caret source=\(location.source.rawValue) app=\(self.context.frontmostBundleID ?? "?")")
            #endif
        }
    }

    private func hidePicker() {
        pickerShown = false
        panel.orderOut(nil)
    }

    private func resetTracking() {
        apply(machine.handle(.reset))
        hidePicker()
    }

    private func currentStrategy() -> Inserter.Strategy {
        settings.usesPasteMode(context.frontmostBundleID) ? .paste : .unicodeString
    }

    private func commit(index: Int) {
        guard model.results.indices.contains(index) else { return }
        let emoji = model.results[index].emoji
        let deleteCount = machine.deleteCountForCommit
        machine.didCommit()
        hidePicker()
        usage.record(emoji.emoji)
        let text = emoji.rendered(tone: settings.skinTone)
        let strategy = currentStrategy()
        DispatchQueue.main.async { [inserter] in
            inserter.replace(deleteCount: deleteCount, with: text, strategy: strategy)
        }
    }
}
#endif
