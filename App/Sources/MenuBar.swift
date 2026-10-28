#if os(macOS)
import SwiftUI
import AppKit

struct MenuContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var controller: AppController

    var body: some View {
        Text(controller.statusText)
        Divider()
        Toggle("Enabled", isOn: $settings.enabled)
        if !controller.isTrusted {
            Button("Grant Accessibility…") { controller.showOnboarding() }
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit macmoji") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#endif
