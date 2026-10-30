#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI
import RevCore

/// First-run setup: skin tone → launch at login → Accessibility → done.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var flow = OnboardingFlow()
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    let settings: AppSettings
    let launch: LaunchAtLogin
    let permissions: PermissionManager
    var onFinish: (@MainActor () -> Void)?
    private var timer: Timer?

    init(settings: AppSettings, launch: LaunchAtLogin, permissions: PermissionManager) {
        self.settings = settings
        self.launch = launch
        self.permissions = permissions
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTrust() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func pollTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        if flow.accessibilityChanged(granted: trusted) {
            NSApp.activate(ignoringOtherApps: true) // come back from System Settings
        }
    }

    var canGoNext: Bool { flow.canGoNext(accessibilityGranted: isTrusted) }
    func next() { flow.next(accessibilityGranted: isTrusted) }
    func back() { flow.back() }
    func finish() { stop(); onFinish?() }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: OnboardingModel?
    /// Called when the user finishes (not when they close the window).
    var onFinish: (@MainActor () -> Void)?

    var isShowing: Bool { window?.isVisible ?? false }

    func show(settings: AppSettings, launch: LaunchAtLogin, permissions: PermissionManager) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = OnboardingModel(settings: settings, launch: launch, permissions: permissions)
        model.onFinish = { [weak self] in
            guard let self else { return }
            self.onFinish?()
            self.window?.close()
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Set up rev"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: OnboardingView(model: model))
        w.center()
        window = w
        self.model = model
        // LSUIElement apps don't come to the front by themselves.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing partway does not set the completed flag, so onboarding shows again next launch.
        model?.stop()
        model = nil
        window = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.flow.current.title).font(.title2).bold()
                Spacer()
                Text("Step \(model.flow.position) of \(model.flow.steps.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
            ProgressView(value: Double(model.flow.position), total: Double(model.flow.steps.count))
                .padding(.bottom, 18)

            Group {
                switch model.flow.current {
                case .skinTone: SkinToneStep(settings: model.settings)
                case .launchAtLogin: LaunchStep(launch: model.launch)
                case .accessibility: AccessibilityStep(model: model)
                case .finish: FinishStep(settings: model.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if model.flow.canGoBack {
                    Button("Back") { model.back() }
                }
                Spacer()
                if model.flow.isLast {
                    Button("Start using rev") { model.finish() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") { model.next() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canGoNext)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 520, height: 420)
    }
}

private let sampleEmoji = Emoji(emoji: "👋", names: ["wave"], skins: ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])

private struct SkinToneStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Emoji with skin tones (like :wave: or :+1:) will use this tone. You can change it later in Settings.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(SkinTone.allCases, id: \.self) { tone in
                    let selected = settings.skinTone == tone
                    Button { settings.skinTone = tone } label: {
                        Text(sampleEmoji.rendered(tone: tone))
                            .font(.system(size: 34))
                            .frame(width: 58, height: 58)
                            .background(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .help(tone.label)
                    .accessibilityLabel(tone.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Selected: \(settings.skinTone.label)").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct LaunchStep: View {
    @ObservedObject var launch: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("rev only works while it's running. Start it automatically when you log in?")
                .fixedSize(horizontal: false, vertical: true)
            LaunchAtLoginControl(launch: launch)
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("To notice ':' shortcodes, use the arrow/Enter/Tab/Esc keys in the picker, find the text cursor and type the emoji, macOS requires the Accessibility permission.")
                .fixedSize(horizontal: false, vertical: true)
            Text("rev never reads typing in password fields. Emoji usage and enabled clipboard history are stored only on this Mac; sensitive and excluded-app clipboard items are skipped.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isTrusted {
                Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("1. Click “Request Access”, then “Open System Settings”.\n2. Turn on Rev under Privacy & Security → Accessibility.\n3. This step moves on by itself once access is granted.")
                    .font(.callout)
                HStack {
                    Button("Request Access") { model.permissions.requestSystemPrompt() }
                    Button("Open System Settings") { model.permissions.openAccessibilitySettings() }
                }
            }
        }
    }
}

private struct FinishStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("🎉").font(.system(size: 48))
            Text("Try typing **:thu** in any text field, then press Enter.")
            Text("↑/↓ choose · Enter or Tab insert · Esc dismiss · type `:fire:` to auto-replace.")
                .font(.callout).foregroundStyle(.secondary)
            if let shortcutDisplay {
                Text("Press \(shortcutDisplay) to open Tools: Emoji Picker, Clipboard History, and Snippets.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Open Tools from the smiley menu to use Emoji Picker, Clipboard History, and Snippets.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("rev lives in the menu bar (the smiley). It's off in Slack and Discord by default.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcutDisplay: String? {
        switch settings.toolsShortcutMode {
        case .disabled:
            return nil
        case .modifierChord:
            return GlobalHotKeyConfiguration.modifierDisplay(settings.toolsChordModifiers)
        case .regularKey:
            return GlobalHotKeyConfiguration(
                key: settings.toolsHotKeyKey,
                modifiers: settings.toolsHotKeyModifiers
            ).displayString
        }
    }
}
#endif
