#if os(macOS)
import AppKit
import CoreGraphics
import Carbon.HIToolbox

/// Replaces typed text using synthesized events.
@MainActor
final class Inserter {
    enum Strategy { case unicodeString, paste }
    var onPasteboardChange: (@MainActor (Int) -> Void)?

    private static let transientPasteboardType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )
    private typealias PasteboardSnapshot = [[(NSPasteboard.PasteboardType, Data)]]
    private static var pasteTransactionID: UUID?
    private static var rootPasteboardSnapshot: PasteboardSnapshot?
    private static var temporaryChangeCount: Int?
    private let source = CGEventSource(stateID: .privateState)
    /// Pause between synthesized events (microseconds).
    private let spacing: useconds_t = 2_000

    init() {
        source?.userData = KeyTap.selfEventTag
    }

    func replace(deleteCount: Int, with text: String, strategy: Strategy) {
        deleteCharacters(deleteCount)
        switch strategy {
        case .unicodeString: typeUnicode(text)
        case .paste: paste(text, cursorOffset: 0)
        }
    }

    /// Snippets always use a transient clipboard paste, then move to their `{cursor}` position.
    func replaceSnippet(deleteCount: Int, with text: String, cursorOffset: Int) {
        deleteCharacters(deleteCount)
        paste(text, cursorOffset: cursorOffset)
    }

    func deleteCharacters(_ count: Int) {
        for _ in 0..<count { tapKey(CGKeyCode(kVK_Delete)) }
    }

    func pasteCurrentClipboard() {
        tapKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    // MARK: Events

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: KeyTap.selfEventTag)
        event.post(tap: .cghidEventTap)
        usleep(spacing)
    }

    private func tapKey(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        post(down)
        post(up)
    }

    /// Types `text` with keyboardSetUnicodeString, chunked on grapheme boundaries
    /// (≤ 20 UTF-16 units per event) so ZWJ / skin-tone sequences are not split mid-cluster.
    private func typeUnicode(_ text: String) {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for ch in text {
            let units = Array(String(ch).utf16)
            if !current.isEmpty && current.count + units.count > 20 { chunks.append(current); current = [] }
            current += units
        }
        if !current.isEmpty { chunks.append(current) }

        for var chunk in chunks {
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.flags = []
            up?.flags = []
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            post(down)
            post(up)
        }
    }

    /// Clipboard fallback: save every item/type, paste, then restore if nobody else changed it.
    private func paste(_ text: String, cursorOffset: Int) {
        let pb = NSPasteboard.general
        let continuesActiveTransaction: Bool
        if Self.pasteTransactionID != nil, let changeCount = Self.temporaryChangeCount {
            continuesActiveTransaction = pb.changeCount == changeCount
        } else {
            continuesActiveTransaction = false
        }
        let saved = continuesActiveTransaction
            ? (Self.rootPasteboardSnapshot ?? snapshot(pb))
            : snapshot(pb)
        let transactionID = UUID()
        Self.pasteTransactionID = transactionID
        Self.rootPasteboardSnapshot = saved

        pb.clearContents()
        let temporaryItem = NSPasteboardItem()
        temporaryItem.setString(text, forType: .string)
        temporaryItem.setData(Data(), forType: Self.transientPasteboardType)
        guard pb.writeObjects([temporaryItem]) else {
            restore(saved, to: pb)
            clearPasteTransaction(id: transactionID)
            onPasteboardChange?(pb.changeCount)
            return
        }
        let ourChange = pb.changeCount
        Self.temporaryChangeCount = ourChange
        onPasteboardChange?(ourChange)

        tapKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        if cursorOffset > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, Self.pasteTransactionID == transactionID else { return }
                for _ in 0..<cursorOffset {
                    self.tapKey(CGKeyCode(kVK_LeftArrow))
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, Self.pasteTransactionID == transactionID else { return }
            guard pb.changeCount == ourChange else {
                self.clearPasteTransaction(id: transactionID)
                return
            }
            self.restore(saved, to: pb)
            self.clearPasteTransaction(id: transactionID)
            self.onPasteboardChange?(pb.changeCount)
        }
    }

    private func snapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    private func clearPasteTransaction(id: UUID) {
        guard Self.pasteTransactionID == id else { return }
        Self.pasteTransactionID = nil
        Self.rootPasteboardSnapshot = nil
        Self.temporaryChangeCount = nil
    }

    private func restore(
        _ snapshot: PasteboardSnapshot,
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { pairs in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
#endif
