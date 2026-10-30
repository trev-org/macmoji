#if os(macOS)
import AppKit
import RevCore
import SwiftUI

@MainActor
final class SnippetEditorModel: ObservableObject {
    @Published var name = ""
    @Published var keyword = ""
    @Published var text = ""
    @Published var errorText: String?
    private(set) var editingID: UUID?

    var onSave: (@MainActor () throws -> Void)?
    var onCancel: (@MainActor () -> Void)?

    func configure(snippet: Snippet?) {
        editingID = snippet?.id
        name = snippet?.name ?? ""
        keyword = snippet?.keyword ?? ""
        text = snippet?.text ?? ""
        errorText = nil
    }

    func save() {
        do {
            try onSave?()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func insertPlaceholder(_ placeholder: String) {
        text += placeholder
    }
}

struct SnippetEditorView: View {
    @ObservedObject var model: SnippetEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.editingID == nil ? "Create Snippet" : "Edit Snippet")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $model.name)
            TextField("Keyword (optional, for example ;sig)", text: $model.keyword)

            HStack {
                Text("Text").font(.headline)
                Spacer()
                Menu("Insert Placeholder") {
                    placeholderButton("{clipboard}")
                    placeholderButton("{date}")
                    placeholderButton("{time}")
                    placeholderButton("{datetime}")
                    placeholderButton("{day}")
                    placeholderButton("{cursor}")
                    Divider()
                    placeholderButton(#"{date format="MMM d, yyyy"}"#)
                }
            }
            TextEditor(text: $model.text)
                .font(.body.monospaced())
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )

            if let errorText = model.errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Text("Keywords must be unique. Snippet text can span multiple lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }

    private func placeholderButton(_ placeholder: String) -> some View {
        Button(placeholder) { model.insertPlaceholder(placeholder) }
    }
}

@MainActor
final class SnippetEditorWindowController: NSWindowController {
    private let model = SnippetEditorModel()
    private let store: SnippetStore
    private let onDidSave: @MainActor () -> Void

    init(store: SnippetStore, onDidSave: @escaping @MainActor () -> Void) {
        self.store = store
        self.onDidSave = onDidSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        super.init(window: window)
        window.title = "Snippet"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SnippetEditorView(model: model))
        model.onSave = { [weak self] in try self?.save() }
        model.onCancel = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    var isShowing: Bool { window?.isVisible == true }

    func showNew() {
        model.configure(snippet: nil)
        showEditor()
    }

    func showEdit(_ snippet: Snippet) {
        model.configure(snippet: snippet)
        showEditor()
    }

    private func showEditor() {
        window?.center()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func save() throws {
        let keyword = model.keyword.isEmpty ? nil : model.keyword
        if let id = model.editingID {
            try store.update(id: id, name: model.name, text: model.text, keyword: keyword)
        } else {
            try store.create(name: model.name, text: model.text, keyword: keyword)
        }
        onDidSave()
        close()
    }
}
#endif
