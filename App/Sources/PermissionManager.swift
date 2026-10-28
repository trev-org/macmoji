#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI

/// Accessibility is the one required permission (event tap with .defaultTap, posting events, AX reads).
@MainActor
final class PermissionManager {
    private var window: NSWindow?
    private var pollTimer: Timer?

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that offers to open System Settings > Privacy & Security > Accessibility.
    func requestSystemPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows the onboarding window and polls until the grant appears, then calls `onGranted`.
    func showOnboarding(onGranted: @escaping @MainActor () -> Void) {
        if window == nil {
            let view = OnboardingView(
                requestPrompt: { [weak self] in self?.requestSystemPrompt() },
                openSettings: { [weak self] in self?.openAccessibilitySettings() }
            )
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Welcome to macmoji"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.pollTimer = nil
                self.window?.close()
                onGranted()
            }
        }
    }
}

struct OnboardingView: View {
    let requestPrompt: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("🙂 macmoji needs Accessibility access").font(.title2).bold()
            Text("macmoji watches for ':' followed by a shortcode (like :thu) and replaces it with an emoji. To read keystrokes, swallow the picker's arrow/Enter/Tab/Esc keys, find the text cursor and type the emoji, macOS requires the Accessibility permission.")
                .fixedSize(horizontal: false, vertical: true)
            Text("macmoji never runs in password fields and keeps nothing except which emoji you use (stored locally for ranking).")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("1. Click “Request Access”, then “Open System Settings”.\n2. Turn on macmoji under Privacy & Security → Accessibility.\n3. This window closes by itself once access is granted.")
                .font(.callout)
            HStack {
                Button("Request Access", action: requestPrompt).keyboardShortcut(.defaultAction)
                Button("Open System Settings", action: openSettings)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
#endif
