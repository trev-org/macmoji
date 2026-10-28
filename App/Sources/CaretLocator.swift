#if os(macOS)
import AppKit
import ApplicationServices

/// Finds where to put the picker: AX caret bounds → focused element frame → mouse position.
enum CaretLocator {
    enum Source: String { case caret, elementFrame, mouse }

    struct Location {
        /// Caret rectangle in Cocoa screen coordinates (bottom-left origin).
        let rect: NSRect
        let source: Source
    }

    static func locate() -> Location {
        if let el = AXHelpers.focusedElement() {
            let frame = elementFrame(el)
            if let caret = caretBounds(el), isSane(caret, within: frame) {
                return Location(rect: toCocoa(caret), source: .caret)
            }
            if let frame, frame.width > 0, frame.height > 0 {
                // Bottom-left corner of the element, as a zero-width "caret".
                let r = CGRect(x: frame.minX + 4, y: frame.maxY - 20, width: 0, height: 20)
                return Location(rect: toCocoa(r), source: .elementFrame)
            }
        }
        let m = NSEvent.mouseLocation
        return Location(rect: NSRect(x: m.x, y: m.y - 10, width: 0, height: 20), source: .mouse)
    }

    /// AX caret bounds in AX (top-left origin) coordinates.
    private static func caretBounds(_ el: AXUIElement) -> CGRect? {
        guard let rangeValue = AXHelpers.axValue(el, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        var useTrailingEdge = false
        if range.length == 0 && range.location > 0 {
            // Bounds of an empty range are often zero; use the character before the caret.
            range = CFRange(location: range.location - 1, length: 1)
            useTrailingEdge = true
        }
        guard let query = AXValueCreate(.cfRange, &range) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            el, kAXBoundsForRangeParameterizedAttribute as CFString, query, &boundsRef) == .success,
            let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil } // swiftlint:disable:this force_cast
        if useTrailingEdge { rect = CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height) }
        return rect
    }

    private static func elementFrame(_ el: AXUIElement) -> CGRect? {
        guard let posV = AXHelpers.axValue(el, kAXPositionAttribute),
              let sizeV = AXHelpers.axValue(el, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posV, .cgPoint, &pos), AXValueGetValue(sizeV, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// Rejects (0,0)-ish garbage and rects outside the focused element (e.g. Monaco's hidden textarea).
    private static func isSane(_ r: CGRect, within frame: CGRect?) -> Bool {
        guard r.height > 0, !(r.origin.x == 0 && r.origin.y == 0) else { return false }
        guard let frame, frame.width > 0, frame.height > 0 else { return true }
        return frame.insetBy(dx: -8, dy: -8).contains(CGPoint(x: r.minX, y: r.midY))
    }

    /// AX global coordinates have their origin at the top-left of the primary screen.
    static func toCocoa(_ r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
#endif
