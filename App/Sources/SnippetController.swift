#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Dispatch
import MacmojiCore
import UniformTypeIdentifiers

@MainActor
final class SnippetController: ObservableObject {
    static let shared = SnippetController()

    @Published private(set) var isShowing = false

    let model: SnippetModel
    private let store: SnippetStore
    private let inserter = Inserter()
    private var cachedKeywordIndex: SnippetKeywordIndex
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var pendingInsertionID: UUID?
    private var hasShownPersistenceError = false

    private lazy var editor = SnippetEditorWindowController(store: store) { [weak self] in
        self?.refreshAfterMutation()
    }

    private lazy var panel: SearchableListPanel = {
        let panel = SearchableListPanel()
        panel.setRootView(SnippetPanelView(
            model: self.model,
            onInsert: { [weak self] in self?.insertSelected() },
            onEdit: { [weak self] in self?.editSelected() },
            onNew: { [weak self] in self?.createSnippet() }
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
        let snippetStore = SnippetStore(
            storage: JSONFileSnippetStorage(
                fileURL: JSONFileSnippetStorage.defaultFileURL()
            )
        )
        store = snippetStore
        model = SnippetModel(store: snippetStore)
        cachedKeywordIndex = SnippetKeywordIndex(
            snippets: snippetStore.snippetsWithKeywords()
        )
        model.onChange = { [weak self] in self?.refreshKeywordIndex() }
        inserter.onPasteboardChange = { changeCount in
            ClipboardHistoryController.shared.ignorePasteboardChange(changeCount)
        }
        if let message = snippetStore.persistenceErrorDescription {
            NSLog("macmoji: \(message)")
        }
    }

    var isCapturingKeyboard: Bool {
        isShowing || editor.isShowing
    }

    var keywordIndex: SnippetKeywordIndex {
        cachedKeywordIndex
    }

    func showSnippets(
        previousApplication: NSRunningApplication? = nil,
        focusedElement: AXUIElement? = nil,
        toolLaunchContext: ToolLaunchContext? = nil
    ) {
        pendingInsertionID = nil
        panel.toolLaunchContext = toolLaunchContext
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
        if !hasShownPersistenceError, let message = store.persistenceErrorDescription {
            hasShownPersistenceError = true
            showAlert(title: "Couldn’t Load Snippets", message: message)
        }
        model.reset()
        isShowing = true
        panel.showOnActiveScreen()
    }

    func createSnippet() {
        if isShowing { panel.hide() }
        editor.showNew()
    }

    func editSelected() {
        guard let selected = model.selected else { return }
        if isShowing { panel.hide() }
        editor.showEdit(selected)
    }

    func expandKeyword(_ match: SnippetKeywordMatch) {
        guard let snippet = store.snippet(id: match.snippetID) else { return }
        let expansion = expansion(for: snippet)
        store.recordUse(id: snippet.id)
        model.refresh()
        inserter.replaceSnippet(
            deleteCount: match.deleteCount,
            with: expansion.text,
            cursorOffset: expansion.cursorOffset
        )
    }

    func importSnippets() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Snippets"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            do {
                let summary = try store.importData(Data(contentsOf: url))
                store.flush()
                if let message = store.persistenceErrorDescription {
                    throw SnippetStoreError.persistenceUnavailable(message)
                }
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.refreshAfterMutation()
                        self?.showImportSummary(summary)
                    }
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.showAlert(title: "Couldn’t Import Snippets", message: message)
                    }
                }
            }
        }
    }

    func exportSnippets() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Snippets"
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "Macmoji Snippets.json"
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            do {
                try store.exportData().write(to: url, options: .atomic)
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.showAlert(title: "Couldn’t Export Snippets", message: message)
                    }
                }
            }
        }
    }

    func flush() {
        store.flush()
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
            insertSelected()
            return true
        case kVK_Escape:
            closeAndRestoreFocus()
            return true
        case kVK_ANSI_E where command:
            editSelected()
            return true
        case kVK_ANSI_N where command:
            createSnippet()
            return true
        case kVK_Delete, kVK_ForwardDelete:
            guard command else { return false }
            model.deleteSelected()
            return true
        default:
            return false
        }
    }

    private func insertSelected() {
        guard let application = previousApplication, !application.isTerminated else {
            NSSound.beep()
            return
        }
        guard let snippet = model.selected else { return }
        let expansion = expansion(for: snippet)
        let operationID = UUID()
        pendingInsertionID = operationID
        panel.hide()
        guard application.activate() else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.insertWhenFrontmost(
                application,
                snippetID: snippet.id,
                expansion: expansion,
                operationID: operationID,
                attemptsRemaining: 20
            )
        }
    }

    private func insertWhenFrontmost(
        _ application: NSRunningApplication,
        snippetID: UUID,
        expansion: SnippetExpansion,
        operationID: UUID,
        attemptsRemaining: Int
    ) {
        guard pendingInsertionID == operationID else { return }
        guard !application.isTerminated else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier {
            pendingInsertionID = nil
            guard restoreFocusedElement() else {
                NSSound.beep()
                return
            }
            store.recordUse(id: snippetID)
            model.refresh()
            inserter.replaceSnippet(
                deleteCount: 0,
                with: expansion.text,
                cursorOffset: expansion.cursorOffset
            )
            return
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            // The user chose another app while activation was pending.
            pendingInsertionID = nil
            return
        }
        guard attemptsRemaining > 0 else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.insertWhenFrontmost(
                application,
                snippetID: snippetID,
                expansion: expansion,
                operationID: operationID,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func closeAndRestoreFocus() {
        pendingInsertionID = nil
        let application = previousApplication
        panel.hide()
        guard let application, !application.isTerminated else { return }
        let operationID = UUID()
        pendingInsertionID = operationID
        guard application.activate() else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        restoreFocusWhenFrontmost(
            application,
            operationID: operationID,
            attemptsRemaining: 20
        )
    }

    private func expansion(for snippet: Snippet) -> SnippetExpansion {
        SnippetExpansionEngine.expand(
            snippet.text,
            context: SnippetExpansionContext(
                clipboard: NSPasteboard.general.string(forType: .string) ?? ""
            )
        )
    }

    private func restoreFocusWhenFrontmost(
        _ application: NSRunningApplication,
        operationID: UUID,
        attemptsRemaining: Int
    ) {
        guard pendingInsertionID == operationID, !application.isTerminated else {
            pendingInsertionID = nil
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier {
            pendingInsertionID = nil
            if !restoreFocusedElement() { NSSound.beep() }
            return
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pendingInsertionID = nil
            return
        }
        guard attemptsRemaining > 0 else {
            pendingInsertionID = nil
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.restoreFocusWhenFrontmost(
                application,
                operationID: operationID,
                attemptsRemaining: attemptsRemaining - 1
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

    private func showImportSummary(_ summary: SnippetImportSummary) {
        var message = "Imported \(summary.importedCount) snippet"
        if summary.importedCount != 1 { message += "s" }
        if summary.skippedCount > 0 {
            message += ". Skipped \(summary.skippedCount) invalid or duplicate entr"
            message += summary.skippedCount == 1 ? "y." : "ies."
        } else {
            message += "."
        }
        showAlert(title: "Import Complete", message: message)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func refreshAfterMutation() {
        refreshKeywordIndex()
        model.refresh()
    }

    private func refreshKeywordIndex() {
        cachedKeywordIndex = SnippetKeywordIndex(
            snippets: store.snippetsWithKeywords()
        )
    }
}
#endif
