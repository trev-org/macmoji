#if os(macOS)
import AppKit
import CoreGraphics
import Carbon.HIToolbox

/// Replaces the typed ":shortcode" with an emoji using synthesized events.
@MainActor
final class Inserter {
    enum Strategy { case unicodeString, paste }
    var onPasteboardChange: (@MainActor (Int) -> Void)?

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
        case .paste: paste(text)
        }
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
    private func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChange = pb.changeCount
        onPasteboardChange?(ourChange)

        tapKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard pb.changeCount == ourChange else { return } // a clipboard manager or the user changed it
            pb.clearContents()
            let items: [NSPasteboardItem] = saved.map { pairs in
                let item = NSPasteboardItem()
                for (type, data) in pairs { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
            self.onPasteboardChange?(pb.changeCount)
        }
    }
}
#endif
