#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import MacmojiCore

@MainActor
final class ToolsController: ObservableObject {
    static let shared = ToolsController()

    private enum ActivePanel {
        case none
        case tools
        case emoji
    }

    @Published private(set) var hotKeyError: String?
    @Published private var activePanel: ActivePanel = .none

    var isShowing: Bool { activePanel != .none }

    private let settings = AppSettings.shared
    private let globalHotKey = GlobalHotKey()
    private let inserter = Inserter()
    private let toolModel: ToolLauncherModel
    private let emojiModel = StandaloneEmojiModel()
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var pendingInsertionID: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    private lazy var toolsPanel: SearchableListPanel = {
        let panel = SearchableListPanel(size: NSSize(width: 430, height: 300))
        panel.setRootView(ToolLauncherView(
            model: self.toolModel,
            onOpen: { [weak self] in self?.openSelectedTool() }
        ))
        panel.handleKeyEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handleToolsKey(event) ?? false }
        }
        panel.onHide = { [weak self] in
            MainActor.assumeIsolated {
                guard self?.activePanel == .tools else { return }
                self?.activePanel = .none
            }
        }
        return panel
    }()

    private lazy var emojiPanel: SearchableListPanel = {
        let panel = SearchableListPanel(size: NSSize(width: 430, height: 460))
        panel.setRootView(StandaloneEmojiView(
            model: self.emojiModel,
            onChoose: { [weak self] in self?.insertSelectedEmoji() }
        ))
        panel.handleKeyEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handleEmojiKey(event) ?? false }
        }
        panel.onHide = { [weak self] in
            MainActor.assumeIsolated {
                guard self?.activePanel == .emoji else { return }
                self?.activePanel = .none
            }
        }
        return panel
    }()

    private init() {
        var registry = ToolRegistry()
        registry.register(MacmojiTool(
            id: "emoji",
            name: "Emoji Picker",
            keywords: ["emoji", "smiley", "reaction"],
            systemImageName: "face.smiling"
        ))
        registry.register(MacmojiTool(
            id: "clipboard",
            name: "Clipboard History",
            keywords: ["clipboard", "history", "paste"],
            systemImageName: "clipboard"
        ))
        registry.register(MacmojiTool(
            id: "snippets",
            name: "Snippets",
            keywords: ["snippet", "text", "template", "expand"],
            systemImageName: "text.quote"
        ))
        toolModel = ToolLauncherModel(registry: registry)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        inserter.onPasteboardChange = { changeCount in
            ClipboardHistoryController.shared.ignorePasteboardChange(changeCount)
        }
        synchronizeShortcut()
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.synchronizeShortcut() }
        }.store(in: &cancellables)
    }

    var shortcutDisplay: String? {
        switch settings.toolsShortcutMode {
        case .disabled:
            return nil
        case .modifierChord:
            return GlobalHotKeyConfiguration.modifierDisplay(settings.toolsChordModifiers)
        case .regularKey:
            return GlobalHotKeyConfiguration(
                key: settings.toolsHotKeyKey,
                modifiers: settings.toolsHotKeyModifiers
            ).displayString
        }
    }

    func showTools() {
        guard !isShowing,
              !ClipboardHistoryController.shared.isShowing,
              !SnippetController.shared.isCapturingKeyboard else { return }
        capturePreviousFocus()
        pendingInsertionID = nil
        toolModel.reset()
        activePanel = .tools
        toolsPanel.showOnActiveScreen()
    }

    private func synchronizeShortcut() {
        globalHotKey.unregister()
        hotKeyError = nil
        guard settings.toolsShortcutMode == .regularKey else { return }
        let configuration = GlobalHotKeyConfiguration(
            key: settings.toolsHotKeyKey,
            modifiers: settings.toolsHotKeyModifiers
        )
        let registered = globalHotKey.register(configuration) { [weak self] in
            self?.showTools()
        }
        if !registered {
            hotKeyError = "Could not register \(configuration.displayString). It may be in use."
        }
    }

    private func capturePreviousFocus() {
        let candidate = NSWorkspace.shared.frontmostApplication
        if let candidate,
           !candidate.isTerminated,
           candidate.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = candidate
            previousFocusedElement = AXHelpers.focusedElement()
        } else {
            previousApplication = nil
            previousFocusedElement = nil
        }
    }

    private func openSelectedTool() {
        guard let tool = toolModel.selected else { return }
        switch tool.id {
        case "emoji":
            toolsPanel.hide()
            emojiModel.reset(tone: settings.skinTone)
            activePanel = .emoji
            emojiPanel.showOnActiveScreen()

        case "clipboard":
            guard settings.clipboardHistoryEnabled else {
                NSSound.beep()
                return
            }
            toolsPanel.hide()
            activePanel = .none
            ClipboardHistoryController.shared.showHistory(
                previousApplication: previousApplication,
                focusedElement: previousFocusedElement
            )

        case "snippets":
            toolsPanel.hide()
            activePanel = .none
            SnippetController.shared.showSnippets(
                previousApplication: previousApplication,
                focusedElement: previousFocusedElement
            )

        default:
            break
        }
    }

    private func handleToolsKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            toolModel.move(-1)
            return true
        case kVK_DownArrow:
            toolModel.move(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            openSelectedTool()
            return true
        case kVK_Escape:
            closeAndRestoreFocus()
            return true
        default:
            return false
        }
    }

    private func handleEmojiKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            emojiModel.move(-1)
            return true
        case kVK_DownArrow:
            emojiModel.move(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            insertSelectedEmoji()
            return true
        case kVK_Escape:
            closeAndRestoreFocus()
            return true
        default:
            return false
        }
    }

    private func insertSelectedEmoji() {
        guard let result = emojiModel.selected,
              let application = previousApplication,
              !application.isTerminated else {
            NSSound.beep()
            return
        }
        let operationID = UUID()
        pendingInsertionID = operationID
        emojiPanel.hide()
        guard application.activate() else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        waitForTarget(
            application,
            operationID: operationID,
            attemptsRemaining: 20
        ) { [weak self] in
            guard let self else { return }
            AppController.shared.recordEmojiUsage(result.emoji)
            let text = result.emoji.rendered(tone: self.settings.skinTone)
            self.inserter.replace(deleteCount: 0, with: text, strategy: .paste)
        }
    }

    private func closeAndRestoreFocus() {
        pendingInsertionID = nil
        switch activePanel {
        case .tools: toolsPanel.hide()
        case .emoji: emojiPanel.hide()
        case .none: break
        }
        guard let application = previousApplication, !application.isTerminated else { return }
        application.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.restoreFocusedElement()
        }
    }

    private func waitForTarget(
        _ application: NSRunningApplication,
        operationID: UUID,
        attemptsRemaining: Int,
        action: @escaping @MainActor () -> Void
    ) {
        guard pendingInsertionID == operationID, !application.isTerminated else {
            pendingInsertionID = nil
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier {
            pendingInsertionID = nil
            guard restoreFocusedElement() else {
                NSSound.beep()
                return
            }
            action()
            return
        }
        guard attemptsRemaining > 0 else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForTarget(
                application,
                operationID: operationID,
                attemptsRemaining: attemptsRemaining - 1,
                action: action
            )
        }
    }

    @discardableResult
    private func restoreFocusedElement() -> Bool {
        guard let previousFocusedElement else { return true }
        return AXUIElementSetAttributeValue(
            previousFocusedElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }
}
#endif
