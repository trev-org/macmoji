#if os(macOS)
import SwiftUI
import AppKit
import RevCore

@main
struct RevApp: App {
    private static let menuBarIconName = "MenuBarIcon"
    private static let menuBarIcon: NSImage? = {
        let name = NSImage.Name(menuBarIconName)
        let image = NSImage(named: name) ?? Bundle.main
            .url(forResource: menuBarIconName, withExtension: "svg")
            .flatMap { NSImage(contentsOf: $0) }
        guard let image else {
            NSLog("rev: failed to load the menu bar icon")
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        if NSImage(named: name) == nil {
            _ = image.setName(name)
        }
        guard NSImage(named: name) != nil else {
            NSLog("rev: failed to register the menu bar icon")
            return nil
        }
        return image
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var clipboardHistory: ClipboardHistoryController
    @StateObject private var tools: ToolsController
    @StateObject private var snippets: SnippetController

    init() {
        _ = Self.menuBarIcon
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
        MenuBarExtra("rev", image: Self.menuBarIconName) {
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
