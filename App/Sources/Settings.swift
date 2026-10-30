#if os(macOS)
import Foundation
import Combine
import MacmojiCore

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Apps with their own ':' picker. Disabled by default (plan decision 7).
    static let defaultBlocklist = [
        "com.tinyspeck.slackmacgap",   // Slack
        "com.hnc.Discord",             // Discord
        "com.hnc.DiscordPTB",
        "com.hnc.DiscordCanary",
    ]
    /// Apps where unicode-string typing is unreliable; use clipboard paste instead.
    static let defaultPasteModeApps = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]

    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var blocklist: [String] { didSet { defaults.set(blocklist, forKey: "blocklist") } }
    @Published var pasteModeApps: [String] { didSet { defaults.set(pasteModeApps, forKey: "pasteModeApps") } }
    @Published var skinTone: SkinTone { didSet { defaults.set(skinTone.rawValue, forKey: "skinTone") } }
    @Published var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: "clipboardHistoryEnabled") }
    }
    @Published var clipboardHistoryPaused: Bool {
        didSet { defaults.set(clipboardHistoryPaused, forKey: "clipboardHistoryPaused") }
    }
    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: "clipboardRetention") }
    }
    @Published var clipboardExcludedApps: [String] {
        didSet { defaults.set(clipboardExcludedApps, forKey: "clipboardExcludedApps") }
    }
    @Published var toolsShortcutMode: ToolsShortcutMode {
        didSet { defaults.set(toolsShortcutMode.rawValue, forKey: "toolsShortcutMode") }
    }
    @Published var toolsChordModifiers: Int {
        didSet { defaults.set(toolsChordModifiers, forKey: "toolsChordModifiers") }
    }
    @Published var toolsHotKeyKey: String {
        didSet { defaults.set(toolsHotKeyKey, forKey: "toolsHotKeyKey") }
    }
    @Published var toolsHotKeyModifiers: Int {
        didSet { defaults.set(toolsHotKeyModifiers, forKey: "toolsHotKeyModifiers") }
    }
    @Published var snippetExpansionEnabled: Bool {
        didSet { defaults.set(snippetExpansionEnabled, forKey: "snippetExpansionEnabled") }
    }
    @Published var snippetRequiresWordBoundary: Bool {
        didSet {
            defaults.set(snippetRequiresWordBoundary, forKey: "snippetRequiresWordBoundary")
        }
    }
    @Published var snippetExcludedApps: [String] {
        didSet { defaults.set(snippetExcludedApps, forKey: "snippetExcludedApps") }
    }
    /// Set only when the user finishes onboarding (closing it partway leaves this false).
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: OnboardingFlow.completedDefaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "enabled": true,
            "blocklist": Self.defaultBlocklist,
            "pasteModeApps": Self.defaultPasteModeApps,
            "skinTone": SkinTone.none.rawValue,
            "clipboardHistoryEnabled": true,
            "clipboardHistoryPaused": false,
            "clipboardRetention": ClipboardRetention.sevenDays.rawValue,
            "clipboardExcludedApps": ClipboardPrivacy.defaultExcludedBundleIdentifiers,
            "toolsShortcutMode": ToolsShortcutMode.modifierChord.rawValue,
            "toolsChordModifiers":
                GlobalHotKeyConfiguration.option | GlobalHotKeyConfiguration.command,
            "toolsHotKeyKey": "V",
            "toolsHotKeyModifiers": GlobalHotKeyConfiguration.defaultModifiers,
            "snippetExpansionEnabled": true,
            "snippetRequiresWordBoundary": true,
            "snippetExcludedApps": [],
        ])
        enabled = defaults.bool(forKey: "enabled")
        blocklist = defaults.stringArray(forKey: "blocklist") ?? Self.defaultBlocklist
        pasteModeApps = defaults.stringArray(forKey: "pasteModeApps") ?? Self.defaultPasteModeApps
        skinTone = SkinTone(rawValue: defaults.integer(forKey: "skinTone")) ?? .none
        clipboardHistoryEnabled = defaults.bool(forKey: "clipboardHistoryEnabled")
        clipboardHistoryPaused = defaults.bool(forKey: "clipboardHistoryPaused")
        clipboardRetention = ClipboardRetention(
            rawValue: defaults.string(forKey: "clipboardRetention") ?? ""
        ) ?? .sevenDays
        clipboardExcludedApps = defaults.stringArray(forKey: "clipboardExcludedApps")
            ?? ClipboardPrivacy.defaultExcludedBundleIdentifiers
        toolsShortcutMode = ToolsShortcutMode(
            rawValue: defaults.string(forKey: "toolsShortcutMode") ?? ""
        ) ?? .modifierChord
        let chordModifiers = defaults.integer(forKey: "toolsChordModifiers")
        toolsChordModifiers = chordModifiers == 0
            ? GlobalHotKeyConfiguration.option | GlobalHotKeyConfiguration.command
            : chordModifiers
        toolsHotKeyKey = defaults.string(forKey: "toolsHotKeyKey") ?? "V"
        let hotKeyModifiers = defaults.integer(forKey: "toolsHotKeyModifiers")
        toolsHotKeyModifiers = hotKeyModifiers == 0
            ? GlobalHotKeyConfiguration.defaultModifiers
            : hotKeyModifiers
        snippetExpansionEnabled = defaults.bool(forKey: "snippetExpansionEnabled")
        snippetRequiresWordBoundary = defaults.bool(forKey: "snippetRequiresWordBoundary")
        snippetExcludedApps = defaults.stringArray(forKey: "snippetExcludedApps") ?? []
        onboardingCompleted = defaults.bool(forKey: OnboardingFlow.completedDefaultsKey)
    }

    func isBlocked(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return blocklist.contains(bundleID)
    }

    func usesPasteMode(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return pasteModeApps.contains(bundleID)
    }

    func excludesSnippetExpansion(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return snippetExcludedApps.contains {
            $0.caseInsensitiveCompare(bundleID) == .orderedSame
        }
    }
}
#endif
