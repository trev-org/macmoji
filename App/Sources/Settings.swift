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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "enabled": true,
            "blocklist": Self.defaultBlocklist,
            "pasteModeApps": Self.defaultPasteModeApps,
            "skinTone": SkinTone.none.rawValue,
        ])
        enabled = defaults.bool(forKey: "enabled")
        blocklist = defaults.stringArray(forKey: "blocklist") ?? Self.defaultBlocklist
        pasteModeApps = defaults.stringArray(forKey: "pasteModeApps") ?? Self.defaultPasteModeApps
        skinTone = SkinTone(rawValue: defaults.integer(forKey: "skinTone")) ?? .none
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
