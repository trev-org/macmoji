#if os(macOS)
import AppKit
import MacmojiCore
import SwiftUI

@MainActor
final class SnippetModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published private(set) var snippets: [Snippet] = []
    @Published var selection = 0
    @Published private(set) var scrollRequest = 0

    private let store: SnippetStore
    var onChange: (@MainActor () -> Void)?

    init(store: SnippetStore) {
        self.store = store
        refresh()
    }

    var selected: Snippet? {
        snippets.indices.contains(selection) ? snippets[selection] : nil
    }

    func reset() {
        query = ""
        selection = 0
        refresh()
        scrollRequest += 1
    }

    func refresh() {
        let selectedID = selected?.id
        snippets = store.search(query)
        if let selectedID, let index = snippets.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = min(selection, max(0, snippets.count - 1))
        }
    }

    func select(_ index: Int) {
        guard snippets.indices.contains(index) else { return }
        selection = index
    }

    func move(_ delta: Int) {
        guard !snippets.isEmpty else { return }
        selection = (selection + delta + snippets.count) % snippets.count
    }

    func deleteSelected() {
        guard let selected else { return }
        guard store.delete(id: selected.id) else { return }
        refresh()
        onChange?()
    }
}

struct SnippetPanelView: View {
    @ObservedObject var model: SnippetModel
    let onInsert: @MainActor () -> Void
    let onEdit: @MainActor () -> Void
    let onNew: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search snippets", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            }
            .padding(14)

            Divider()

            HStack(spacing: 0) {
                snippetList.frame(width: 340)
                Divider()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            Text("↩ Insert   ⌘E Edit   ⌘N New   ⌘⌫ Delete   Esc Close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .frame(
            width: SearchableListPanel.panelSize.width,
            height: SearchableListPanel.panelSize.height
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
    }

    private var snippetList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.snippets.enumerated()), id: \.element.id) { index, snippet in
                        SnippetRow(snippet: snippet, selected: index == model.selection)
                            .id(snippet.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(index) }
                            .onTapGesture(count: 2) { model.select(index); onInsert() }
                    }
                    if model.snippets.isEmpty {
                        ContentUnavailableView(
                            "No Snippets",
                            systemImage: "text.quote",
                            description: Text("Create a snippet or try another search.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, index in
                guard model.snippets.indices.contains(index) else { return }
                proxy.scrollTo(model.snippets[index].id, anchor: .center)
            }
            .onChange(of: model.scrollRequest) {
                guard let selected = model.selected else { return }
                proxy.scrollTo(selected.id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let snippet = model.selected {
            SnippetPreview(snippet: snippet)
        } else {
            ContentUnavailableView("No Selection", systemImage: "text.quote")
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.quote").frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let keyword = snippet.keyword {
                        Text(keyword).font(.caption2.monospaced())
                    }
                    Text(snippet.text.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SnippetPreview: View {
    let snippet: Snippet

    private var expansion: SnippetExpansion {
        SnippetExpansionEngine.expand(
            snippet.text,
            context: SnippetExpansionContext(
                clipboard: NSPasteboard.general.string(forType: .string) ?? ""
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(expansion.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if let keyword = snippet.keyword {
                    Label(keyword, systemImage: "keyboard")
                        .font(.caption.monospaced())
                }
                Label("\(snippet.useCount) uses", systemImage: "arrow.counterclockwise")
                Label(
                    snippet.modifiedAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "pencil"
                )
                if expansion.cursorOffset > 0 {
                    Label(
                        "Caret moves \(expansion.cursorOffset) characters left",
                        systemImage: "character.cursor.ibeam"
                    )
                }
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }
}
#endif
