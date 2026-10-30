#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Combine
import Dispatch
import MacmojiCore

/// Wires the event tap, state machine, search, picker and inserter together.
/// Everything runs on the main thread (the tap's run loop source is on the main run loop).
@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var statusText = "Starting…"
    /// False until onboarding has finished at least once; nothing is captured before that.
    @Published private(set) var hasStarted = false

    private let settings = AppSettings.shared
    private let permissions = PermissionManager()
    private let onboarding = OnboardingWindowController()
    private let context = AppContext()
    private let inserter = Inserter()
    private let usage = UsageStore(fileURL: UsageStore.defaultFileURL())
    private let clipboardCommand = PickerCommand(
        id: "clipboard-history",
        name: "Clipboard History",
        aliases: ["clipboard"],
        keywords: ["clipboard", "history", "paste"],
        systemImageName: "clipboard"
    )
    private var search: PickerSearch?
    private var machine = TriggerStateMachine()
    private var toolsChord = ModifierChordStateMachine(chord: [.option, .command])
    private var toolsChordMouseOrigin: CGPoint?
    private lazy var tap = KeyTap { [unowned self] type, event in self.handle(type: type, event: event) }
    private let model = PickerModel()
    private lazy var panel = PickerPanel(model: model)
    private var pickerShown = false
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        do {
            let store = try EmojiStore.bundled()
            let pickerSearch = PickerSearch(
                emojiSearch: EmojiSearch(store: store, usage: usage),
                commands: [clipboardCommand]
            )
            search = pickerSearch
            machine = TriggerStateMachine(isExactName: {
                store.emoji(named: $0) != nil || pickerSearch.exactCommand(named: $0) != nil
            })
        } catch {
            statusText = "Could not load emoji data"
            NSLog("macmoji: failed to load emoji.json: \(error)")
            return
        }
        model.onChoose = { [unowned self] index in self.commit(index: index) }
        inserter.onPasteboardChange = { changeCount in
            ClipboardHistoryController.shared.ignorePasteboardChange(changeCount)
        }
        context.onAppChanged = { [unowned self] in self.resetTracking(); self.refreshStatus() }
        tap.onDisabled = { NSLog("macmoji: event tap was disabled by macOS; re-enabled") }
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshStatus()
                self?.synchronizeToolsChord()
            }
        }.store(in: &cancellables)
        synchronizeToolsChord()

        onboarding.onFinish = { [unowned self] in
            self.settings.onboardingCompleted = true
            self.beginRunning()
        }

        switch LaunchDecision.decide(onboardingCompleted: settings.onboardingCompleted,
                                     accessibilityGranted: AXIsProcessTrusted()) {
        case .onboarding:
            statusText = "Finish setup to start"
            showSetup()
        case .run, .permissionPrompt:
            beginRunning()
        }
    }

    /// Opens the first-run setup window (also from the "Run setup again…" menu item).
    func showSetup() {
        onboarding.show(settings: settings, launch: LaunchAtLogin.shared, permissions: permissions)
    }

    /// Starts normal operation: event tap if trusted, else the Accessibility prompt.
    private func beginRunning() {
        if hasStarted {
            if AXIsProcessTrusted() && !tap.isRunning { startTap() }
            refreshStatus()
            return
        }
        hasStarted = true
        if AXIsProcessTrusted() {
            startTap()
        } else {
            showPermissionPrompt()
        }
        // Watch for the grant being revoked or (re)granted while running.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTrust() }
        }
        refreshStatus()
    }

    func showPermissionPrompt() {
        permissions.showOnboarding { [weak self] in self?.startTap() }
    }

    func clearEmojiHistory() {
        DispatchQueue.global(qos: .utility).async { [usage] in
            do {
                try usage.clear()
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Couldn’t Clear Emoji History"
                        alert.informativeText = message
                        alert.runModal()
                    }
                }
            }
        }
    }

    func flushEmojiHistory() {
        usage.flush()
    }

    func searchEmoji(_ query: String, limit: Int = 12) -> [EmojiSearch.Result] {
        search?.emojiSearch.search(query, limit: limit) ?? []
    }

    func recordEmojiUsage(_ emoji: Emoji) {
        usage.record(emoji.emoji)
    }

    private func startTap() {
        isTrusted = AXIsProcessTrusted()
        if !tap.start() { NSLog("macmoji: CGEvent.tapCreate failed") }
        refreshStatus()
    }

    private func checkTrust() {
        let trusted = AXIsProcessTrusted()
        guard hasStarted, trusted != isTrusted else { return }
        isTrusted = trusted
        if trusted { startTap() } else { tap.stop(); resetTracking() }
        refreshStatus()
    }

    private func refreshStatus() {
        if !hasStarted { statusText = "Finish setup to start"; return }
        if !isTrusted { statusText = "Needs Accessibility permission" }
        else if !tap.isRunning { statusText = "Event tap not running (relaunch macmoji)" }
        else if !settings.enabled { statusText = "Paused" }
        else if settings.isBlocked(context.frontmostBundleID) { statusText = "Off in this app" }
        else { statusText = "Active — type :name" }
    }

    // MARK: Event handling (called from the tap; keep it fast)

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        trackToolsShortcut(type: type, event: event)
        if type == .flagsChanged { return false }

        if ClipboardHistoryController.shared.isShowing || ToolsController.shared.isShowing {
            if pickerShown { resetTracking() }
            return false
        }
        guard type == .keyDown else {
            if Self.isMouseButtonEvent(type) {
                // Clicks inside the picker choose a row; anything else ends tracking.
                if pickerShown && panel.frame.contains(NSEvent.mouseLocation) { return false }
                resetTracking()
            }
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

    private func synchronizeToolsChord() {
        let modifiers = ShortcutModifiers(
            rawValue: UInt8(truncatingIfNeeded: settings.toolsChordModifiers)
        )
        if !modifiers.isEmpty {
            toolsChord.reset(chord: modifiers)
            toolsChordMouseOrigin = nil
        }
    }

    private func trackToolsShortcut(type: CGEventType, event: CGEvent) {
        guard settings.toolsShortcutMode == .modifierChord else {
            toolsChord.interrupt()
            return
        }

        switch type {
        case .flagsChanged:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if !Self.modifierKeyCodes.contains(keyCode) {
                toolsChord.interrupt()
            }
            let modifiers = Self.shortcutModifiers(from: event.flags)
            if let origin = toolsChordMouseOrigin {
                let location = event.location
                let deltaX = location.x - origin.x
                let deltaY = location.y - origin.y
                if deltaX * deltaX + deltaY * deltaY > 1 {
                    toolsChord.interrupt()
                }
            }
            if modifiers.isEmpty {
                toolsChordMouseOrigin = nil
            } else if toolsChordMouseOrigin == nil {
                toolsChordMouseOrigin = event.location
            }
            let action = toolsChord.flagsChanged(
                modifiers: modifiers,
                at: TimeInterval(event.timestamp) / 1_000_000_000
            )
            if action == .trigger {
                if pickerShown { resetTracking() }
                DispatchQueue.main.async {
                    ToolsController.shared.showTools()
                }
            }

        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            toolsChord.interrupt()

        default:
            break
        }
    }

    private static func shortcutModifiers(from flags: CGEventFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand,
        kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl,
        kVK_Shift, kVK_RightShift,
    ]

    private static func isMouseButtonEvent(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
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
            if settings.clipboardHistoryEnabled,
               let command = search?.exactCommand(named: name) {
                commit(command: command, deleteCount: deleteCount, delay: 0.05)
                return
            }
            guard let emoji = search?.emojiSearch.store.emoji(named: name) else { return }
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
        var results = search.search(query, emojiLimit: 8)
        if !settings.clipboardHistoryEnabled {
            results.removeAll {
                if case .command = $0 { return true }
                return false
            }
        }
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
        let deleteCount = machine.deleteCountForCommit
        switch model.results[index] {
        case .command(let match):
            commit(command: match.command, deleteCount: deleteCount, delay: 0)
            return
        case .emoji(let result):
            commit(emoji: result.emoji, deleteCount: deleteCount)
        }
    }

    private func commit(emoji: Emoji, deleteCount: Int) {
        machine.didCommit()
        hidePicker()
        usage.record(emoji.emoji)
        let text = emoji.rendered(tone: settings.skinTone)
        let strategy = currentStrategy()
        DispatchQueue.main.async { [inserter] in
            inserter.replace(deleteCount: deleteCount, with: text, strategy: strategy)
        }
    }

    /// Executes a reusable inline picker command. Future commands (such as Snippets) register here.
    private func commit(command: PickerCommand, deleteCount: Int, delay: TimeInterval) {
        guard settings.clipboardHistoryEnabled, command.id == clipboardCommand.id else { return }
        let targetApplication = NSWorkspace.shared.frontmostApplication
        let focusedElement = AXHelpers.focusedElement()
        machine.didCommit()
        hidePicker()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [inserter] in
            inserter.deleteCharacters(deleteCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                ClipboardHistoryController.shared.showHistory(
                    previousApplication: targetApplication,
                    focusedElement: focusedElement
                )
            }
        }
    }
}
#endif
