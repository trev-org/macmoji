#if os(macOS)
import SwiftUI
import AppKit
import RevCore

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var tools: ToolsController

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
            Section("Tools launcher") {
                Picker("Shortcut", selection: $settings.toolsShortcutMode) {
                    ForEach(ToolsShortcutMode.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                if settings.toolsShortcutMode == .modifierChord {
                    Picker("Modifier chord", selection: $settings.toolsChordModifiers) {
                        ForEach(ModifierChordOption.available) {
                            Text($0.label).tag($0.modifiers)
                        }
                    }
                    Text("Tap and release the modifiers together. Pressing another key cancels it.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if settings.toolsShortcutMode == .regularKey {
                    HStack {
                        Text("Keyboard shortcut")
                        Spacer()
                        HotKeyRecorderView(
                            key: $settings.toolsHotKeyKey,
                            modifiers: $settings.toolsHotKeyModifiers
                        )
                        .frame(width: 140, height: 24)
                    }
                    Text("Click the shortcut field, then press a modified key (including Space).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = tools.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Snippets") {
                Toggle("Expand snippet keywords", isOn: $settings.snippetExpansionEnabled)
                Toggle(
                    "Require a word boundary before keywords",
                    isOn: $settings.snippetRequiresWordBoundary
                )
                .disabled(!settings.snippetExpansionEnabled)
                Text("Keyword expansion always inserts by a temporary clipboard paste, then restores the previous clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Do not expand snippet keywords in these apps") {
                BundleIDListEditor(items: $settings.snippetExcludedApps)
            }
            Section("Clipboard history") {
                Toggle("Enable clipboard history", isOn: $settings.clipboardHistoryEnabled)
                Picker("Keep unpinned items", selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .disabled(!settings.clipboardHistoryEnabled)

                Text("Type :cl or :clipboard to open it inline, or choose it from Tools.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Do not record clipboard items from these apps") {
                BundleIDListEditor(items: $settings.clipboardExcludedApps)
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
        .frame(width: 500, height: 780)
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
