#if os(macOS)
import AppKit
import SwiftUI

/// Owns the Settings window instead of relying on SwiftUI's Settings scene dispatch.
///
/// `LSUIElement` apps do not have a normal Dock/application-menu activation path, so the window
/// must be retained and the app explicitly activated each time Settings is requested.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: AppSettings, tools: ToolsController) {
        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(tools)
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 780),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "rev Settings"
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.collectionBehavior.insert(.moveToActiveSpace)
        settingsWindow.contentView = NSHostingView(rootView: rootView)
        settingsWindow.center()
        super.init(window: settingsWindow)
        settingsWindow.delegate = self
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func show() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Cancels an in-progress HotKeyRecorderField and removes its local key monitor.
        window?.makeFirstResponder(nil)
    }
}
#endif
