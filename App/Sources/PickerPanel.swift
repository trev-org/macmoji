#if os(macOS)
import AppKit
import SwiftUI

/// Borderless, non-activating panel: the target app keeps keyboard focus.
final class PickerPanel: NSPanel {
    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 28
    static let verticalPadding: CGFloat = 12

    init(model: PickerModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = FirstMouseHostingView(rootView: PickerView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the panel below the caret (or above it if there is no room), clamped to the screen.
    func show(rowCount: Int, caret: NSRect) {
        let height = CGFloat(max(rowCount, 1)) * Self.rowHeight + Self.verticalPadding
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(caret.origin) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 10_000, height: 10_000)

        var x = caret.minX - 8
        var y = caret.minY - 4 - height // below the caret line
        if y < visible.minY { y = caret.maxY + 4 } // flip above
        x = min(max(x, visible.minX), visible.maxX - Self.width)
        y = min(max(y, visible.minY), visible.maxY - height)

        setFrame(NSRect(x: x, y: y, width: Self.width, height: height), display: true)
        orderFrontRegardless()
    }

    func resize(rowCount: Int) {
        guard isVisible else { return }
        let height = CGFloat(max(rowCount, 1)) * Self.rowHeight + Self.verticalPadding
        var f = frame
        f.origin.y += f.height - height // keep the top edge fixed
        f.size.height = height
        setFrame(f, display: true)
    }
}

/// Lets row clicks register without activating rev first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
