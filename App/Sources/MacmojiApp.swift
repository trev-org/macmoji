#if os(macOS)
import SwiftUI
import AppKit

@main
struct MacmojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var clipboardHistory = ClipboardHistoryController.shared
    @StateObject private var tools = ToolsController.shared
    @StateObject private var snippets = SnippetController.shared

    var body: some Scene {
        MenuBarExtra("macmoji", systemImage: "face.smiling") {
            MenuContent()
                .environmentObject(settings)
                .environmentObject(AppController.shared)
                .environmentObject(clipboardHistory)
                .environmentObject(tools)
                .environmentObject(snippets)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppController.shared.start()
            ClipboardHistoryController.shared.start()
            ToolsController.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppController.shared.flushEmojiHistory()
            ClipboardHistoryController.shared.flush()
            SnippetController.shared.flush()
        }
    }
}
#endif
