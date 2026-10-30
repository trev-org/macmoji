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
    /// Optional secondary entry point. Off by default; inline `:` commands remain available.
    @Published var clipboardHotKeyEnabled: Bool {
        didSet { defaults.set(clipboardHotKeyEnabled, forKey: "clipboardHotKeyEnabled") }
    }
    @Published var clipboardHotKeyKey: String {
        didSet { defaults.set(clipboardHotKeyKey, forKey: "clipboardHotKeyKey") }
    }
    @Published var clipboardHotKeyModifiers: Int {
        didSet { defaults.set(clipboardHotKeyModifiers, forKey: "clipboardHotKeyModifiers") }
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
            "clipboardHotKeyEnabled": false,
            "clipboardHotKeyKey": "V",
            "clipboardHotKeyModifiers": ClipboardHotKey.defaultModifiers,
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
        clipboardHotKeyEnabled = defaults.bool(forKey: "clipboardHotKeyEnabled")
        clipboardHotKeyKey = defaults.string(forKey: "clipboardHotKeyKey") ?? "V"
        let hotKeyModifiers = defaults.integer(forKey: "clipboardHotKeyModifiers")
        clipboardHotKeyModifiers = hotKeyModifiers == 0
            ? ClipboardHotKey.defaultModifiers
            : hotKeyModifiers
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
}
#endif
