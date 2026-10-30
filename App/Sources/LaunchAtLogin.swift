#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

/// Launch at login via SMAppService.mainApp. The live system status is the source of truth
/// (the user can change it in System Settings → General → Login Items), so nothing is cached.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = (enabled ? "Couldn't turn on launch at login: " : "Couldn't turn off launch at login: ")
                + error.localizedDescription
        }
        refresh()
        if enabled && status == .requiresApproval && errorMessage == nil {
            errorMessage = "macOS needs you to allow rev in System Settings → General → Login Items."
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var statusDescription: String {
        switch status {
        case .enabled: return "On"
        case .notRegistered: return "Off"
        case .requiresApproval: return "Waiting for approval in Login Items"
        case .notFound: return "Not available for this copy of the app"
        @unknown default: return "Unknown"
        }
    }

    /// Login items are most reliable for a signed app in /Applications or ~/Applications.
    var isInstalledInApplications: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder == "/Applications" || folder == home + "/Applications"
    }
}

/// Toggle + status/error + Login Items button, shared by onboarding and Settings.
struct LaunchAtLoginControl: View {
    @ObservedObject var launch: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open rev automatically when I log in", isOn: Binding(
                get: { launch.isEnabled || launch.requiresApproval },
                set: { launch.setEnabled($0) }
            ))
            Text("Status: \(launch.statusDescription)").font(.caption).foregroundStyle(.secondary)
            if let message = launch.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if launch.requiresApproval || launch.errorMessage != nil {
                Button("Open Login Items Settings…") { launch.openLoginItemsSettings() }
            }
            if !launch.isInstalledInApplications {
                Text("Tip: move Rev.app to /Applications for launch at login to work reliably.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { launch.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launch.refresh()
        }
    }
}
#endif
