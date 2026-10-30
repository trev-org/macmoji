#if os(macOS)
import SwiftUI
import AppKit
import RevCore

@main
struct RevApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var clipboardHistory: ClipboardHistoryController
    @StateObject private var tools: ToolsController
    @StateObject private var snippets: SnippetController

    init() {
        let migration = LegacyDataMigration.migrate()
        for error in migration.errors {
            NSLog("rev: legacy data migration failed: \(error)")
        }
        _settings = StateObject(wrappedValue: AppSettings.shared)
        _clipboardHistory = StateObject(wrappedValue: ClipboardHistoryController.shared)
        _tools = StateObject(wrappedValue: ToolsController.shared)
        _snippets = StateObject(wrappedValue: SnippetController.shared)
    }

    var body: some Scene {
        MenuBarExtra("rev", systemImage: "face.smiling") {
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
