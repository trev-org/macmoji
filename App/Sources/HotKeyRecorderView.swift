#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var key: String
    @Binding var modifiers: Int

    func makeNSView(context: Context) -> HotKeyRecorderField {
        let field = HotKeyRecorderField()
        field.onRecord = { key, modifiers in
            self.key = key
            self.modifiers = modifiers
        }
        field.updateDisplay(key: key, modifiers: modifiers)
        return field
    }

    func updateNSView(_ field: HotKeyRecorderField, context: Context) {
        field.onRecord = { key, modifiers in
            self.key = key
            self.modifiers = modifiers
        }
        if !field.isRecording {
            field.updateDisplay(key: key, modifiers: modifiers)
        }
    }
}

final class HotKeyRecorderField: NSTextField {
    var onRecord: ((String, Int) -> Void)?
    private(set) var isRecording = false
    private var savedDisplay = ""
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBezeled = true
        bezelStyle = .roundedBezel
        alignment = .center
        focusRingType = .exterior
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        stringValue = "Press shortcut…"
        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self, self.isRecording else { return event }
                self.record(event)
                return nil
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            stringValue = savedDisplay
            removeEventMonitor()
            window?.makeFirstResponder(nil)
            return
        }
        let modifiers = GlobalHotKeyConfiguration.modifiers(from: event.modifierFlags)
        let safeModifiers = GlobalHotKeyConfiguration.command
            | GlobalHotKeyConfiguration.option
            | GlobalHotKeyConfiguration.control
        guard modifiers & safeModifiers != 0,
              let key = GlobalHotKeyConfiguration.key(for: event.keyCode) else {
            NSSound.beep()
            return
        }
        onRecord?(key, modifiers)
        isRecording = false
        removeEventMonitor()
        updateDisplay(key: key, modifiers: modifiers)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        removeEventMonitor()
        stringValue = savedDisplay
        return super.resignFirstResponder()
    }

    deinit {
        removeEventMonitor()
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    func updateDisplay(key: String, modifiers: Int) {
        savedDisplay = GlobalHotKeyConfiguration(
            key: key,
            modifiers: modifiers
        ).displayString
        stringValue = savedDisplay
    }
}
#endif
