#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import MacmojiCore

/// Reusable keyable panel shell for searchable list features (clipboard now, snippets later).
final class SearchableListPanel: NSPanel {
    static let panelSize = NSSize(width: 820, height: 500)
    var handleKeyEvent: ((NSEvent) -> Bool)?
    var onHide: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setRootView<Content: View>(_ content: Content) {
        contentView = NSHostingView(rootView: content)
    }

    func showOnActiveScreen() {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: point, size: Self.panelSize)
        let origin = NSPoint(
            x: visible.midX - Self.panelSize.width / 2,
            y: visible.midY - Self.panelSize.height / 2
        )
        setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        focusFirstTextField()
    }

    func hide() {
        orderOut(nil)
        onHide?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKeyEvent?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        guard isVisible else { return }
        DispatchQueue.main.async { [weak self] in self?.hide() }
    }

    private func focusFirstTextField() {
        focusFirstTextField(attemptsRemaining: 3)
    }

    private func focusFirstTextField(attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, let contentView else { return }
            if let field = self.firstTextField(in: contentView) {
                self.makeFirstResponder(field)
            } else if attemptsRemaining > 1 {
                self.focusFirstTextField(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    private func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }
}

@MainActor
final class ClipboardHistoryModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published var filter: ClipboardTypeFilter = .all {
        didSet { if filter != oldValue { refresh() } }
    }
    @Published private(set) var items: [ClipboardItem] = []
    @Published var selection = 0
    @Published private(set) var scrollRequest = 0

    private let store: ClipboardHistoryStore

    init(store: ClipboardHistoryStore) {
        self.store = store
        refresh()
    }

    var selected: ClipboardItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func reset() {
        query = ""
        filter = .all
        selection = 0
        refresh()
        scrollRequest += 1
    }

    func refresh() {
        let selectedID = selected?.id
        items = store.search(query, filter: filter)
        if let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = min(selection, max(0, items.count - 1))
        }
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selection = index
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta + items.count) % items.count
    }

    func togglePin() {
        guard let selected else { return }
        store.togglePinned(id: selected.id)
        refresh()
    }

    func deleteSelected() {
        guard let selected else { return }
        store.delete(id: selected.id)
        refresh()
    }

    func thumbnailData(for item: ClipboardItem) -> Data? {
        guard case .image(let image) = item.content else { return nil }
        return store.blobData(named: image.thumbnailBlobName ?? image.blobName)
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var model: ClipboardHistoryModel
    let onPaste: @MainActor () -> Void
    let onCopy: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                Picker("Type", selection: $model.filter) {
                    ForEach(ClipboardTypeFilter.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(14)

            Divider()

            HStack(spacing: 0) {
                historyList.frame(width: 340)
                Divider()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            Text("↩ Paste   ⌘↩ Copy   ⌘P Pin   ⌘⌫ Delete   Esc Close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .frame(width: SearchableListPanel.panelSize.width, height: SearchableListPanel.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        if sectionStarts(at: index) {
                            Text(item.isPinned ? "PINNED" : "RECENT")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.top, index == 0 ? 8 : 12)
                        }
                        ClipboardHistoryRow(item: item, selected: index == model.selection)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(index) }
                            .onTapGesture(count: 2) { model.select(index); onPaste() }
                    }
                    if model.items.isEmpty {
                        ContentUnavailableView(
                            "No Clipboard Items",
                            systemImage: "clipboard",
                            description: Text("Copied items that match this search appear here.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: model.selection) { _, index in
                guard model.items.indices.contains(index) else { return }
                proxy.scrollTo(model.items[index].id, anchor: .center)
            }
            .onChange(of: model.scrollRequest) {
                guard let selected = model.selected else { return }
                proxy.scrollTo(selected.id, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let item = model.selected {
            ClipboardHistoryPreview(item: item, imageData: model.thumbnailData(for: item))
        } else {
            ContentUnavailableView("No Selection", systemImage: "clipboard")
        }
    }

    private func sectionStarts(at index: Int) -> Bool {
        guard model.items.indices.contains(index) else { return false }
        if index == 0 { return true }
        return model.items[index - 1].isPinned != model.items[index].isPinned
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(item.source.name ?? "Unknown app")
                    Text(item.copiedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
            if item.isPinned { Image(systemName: "pin.fill").font(.caption) }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private var title: String {
        item.content.displayText.replacingOccurrences(of: "\n", with: " ")
    }

    private var iconName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .files: return "doc"
        case .color: return "paintpalette"
        }
    }
}

private struct ClipboardHistoryPreview: View {
    let item: ClipboardItem
    let imageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                contentPreview
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label(item.source.name ?? "Unknown app", systemImage: "app")
                if let bundle = item.source.bundleIdentifier {
                    Text(bundle).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Label(item.copiedAt.formatted(date: .abbreviated, time: .standard), systemImage: "clock")
                if let count = item.content.characterCount {
                    Label("\(count) characters", systemImage: "character.cursor.ibeam")
                }
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let value), .link(let value):
            Text(value).textSelection(.enabled)
        case .color(let value):
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: NSColor(hexString: value) ?? .clear))
                    .frame(height: 140)
                Text(value).font(.title2.monospaced()).textSelection(.enabled)
            }
        case .files(let paths):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(paths, id: \.self) { path in
                    Label(path, systemImage: "doc")
                        .textSelection(.enabled)
                }
            }
        case .image:
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 320)
            } else {
                ContentUnavailableView("Preview Unavailable", systemImage: "photo")
            }
        }
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 || value.count == 4 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let red = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? CGFloat(number & 0xff) / 255 : 1
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif
