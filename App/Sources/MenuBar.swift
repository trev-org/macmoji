#if os(macOS)
import SwiftUI
import AppKit

struct MenuContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var clipboardHistory: ClipboardHistoryController

    var body: some View {
        Text(controller.statusText)
        Divider()
        Toggle("Enabled", isOn: $settings.enabled)
        if settings.clipboardHotKeyEnabled {
            Button("Clipboard History…") { clipboardHistory.showHistory() }
                .keyboardShortcut(clipboardShortcutKey, modifiers: clipboardShortcutModifiers)
                .disabled(!settings.clipboardHistoryEnabled)
        } else {
            Button("Clipboard History…") { clipboardHistory.showHistory() }
                .disabled(!settings.clipboardHistoryEnabled)
        }
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
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Clear Emoji History") { controller.clearEmojiHistory() }
        Divider()
        Button("Quit macmoji") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var clipboardShortcutKey: KeyEquivalent {
        KeyEquivalent(settings.clipboardHotKeyKey.lowercased().first ?? "v")
    }

    private var clipboardShortcutModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        let raw = settings.clipboardHotKeyModifiers
        if raw & ClipboardHotKey.command != 0 { modifiers.insert(.command) }
        if raw & ClipboardHotKey.shift != 0 { modifiers.insert(.shift) }
        if raw & ClipboardHotKey.option != 0 { modifiers.insert(.option) }
        if raw & ClipboardHotKey.control != 0 { modifiers.insert(.control) }
        return modifiers
    }
}
#endif
