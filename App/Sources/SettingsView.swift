#if os(macOS)
import SwiftUI
import AppKit
import MacmojiCore

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Enable ':' emoji autocomplete", isOn: $settings.enabled)
                Picker("Default skin tone", selection: $settings.skinTone) {
                    ForEach(SkinTone.allCases, id: \.self) { tone in
                        Text("\(previewThumb(tone))  \(tone.label)").tag(tone)
                    }
                }
            }
            Section("Launch at login") {
                LaunchAtLoginControl(launch: LaunchAtLogin.shared)
            }
            Section("Disabled in these apps (bundle IDs)") {
                BundleIDListEditor(items: $settings.blocklist)
            }
            Section("Insert by clipboard paste in these apps") {
                BundleIDListEditor(items: $settings.pasteModeApps)
                Text("The clipboard is saved and restored around the paste.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }

    private func previewThumb(_ tone: SkinTone) -> String {
        Emoji(emoji: "👍", names: ["+1"], skins: ["👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿"]).rendered(tone: tone)
    }
}

struct BundleIDListEditor: View {
    @Binding var items: [String]
    // Spelled out instead of `@State`: in the macOS 27 SDK `@State` is a macro whose plugin
    // (SwiftUIMacros) ships only with Xcode, so the Command Line Tools build can't expand it.
    // A stored `State` is still picked up by SwiftUI as a dynamic property.
    private let newItemState = State(initialValue: "")
    private var newItem: String {
        get { newItemState.wrappedValue }
        nonmutating set { newItemState.wrappedValue = newValue }
    }

    var body: some View {
        ForEach(items, id: \.self) { item in
            HStack {
                Text(appName(for: item)).frame(maxWidth: .infinity, alignment: .leading)
                Text(item).font(.caption.monospaced()).foregroundStyle(.secondary)
                Button(role: .destructive) { items.removeAll { $0 == item } } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
        }
        HStack {
            TextField("com.example.App", text: newItemState.projectedValue)
                .onSubmit(add)
            Button("Add", action: add).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let id = newItem.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !items.contains(id) else { return }
        items.append(id)
        newItem = ""
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }
}
#endif
