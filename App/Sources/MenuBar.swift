#if os(macOS)
import SwiftUI
import AppKit

struct MenuContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var clipboardHistory: ClipboardHistoryController
    @EnvironmentObject var tools: ToolsController
    @EnvironmentObject var snippets: SnippetController

    var body: some View {
        Text(controller.statusText)
        Divider()
        Toggle("Emoji Autocomplete", isOn: $settings.enabled)
        if let shortcut = tools.shortcutDisplay {
            Button("Tools…  \(shortcut)") { tools.showTools() }
        } else {
            Button("Tools…") { tools.showTools() }
        }
        Button("Snippets…") { snippets.showSnippets() }
        Button("Create Snippet…") { snippets.createSnippet() }
        Button("Import Snippets…") { snippets.importSnippets() }
        Button("Export Snippets…") { snippets.exportSnippets() }
        Divider()
        Button("Clipboard History…") { clipboardHistory.showHistory() }
            .disabled(!settings.clipboardHistoryEnabled)
        Button(settings.clipboardHistoryPaused ? "Resume Clipboard History" : "Pause Clipboard History") {
            clipboardHistory.togglePaused()
        }
        .disabled(!settings.clipboardHistoryEnabled)
        Button("Clear Clipboard History…") { clipboardHistory.confirmClearHistory() }
            .disabled(!settings.clipboardHistoryEnabled)
        Divider()
        if !controller.isTrusted && controller.hasStarted {
            Button("Grant Accessibility…") { controller.showPermissionPrompt() }
        }
        Button("Run setup again…") { controller.showSetup() }
        Button("Settings…") { controller.showSettings() }
            .keyboardShortcut(",")
        Button("Clear Emoji History") { controller.clearEmojiHistory() }
        Divider()
        Button("Quit macmoji") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#endif
