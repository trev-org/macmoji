#if os(macOS)
import CoreGraphics
import Foundation

/// A single blocking (.defaultTap) session event tap for keyDown and mouse-down events.
/// The handler returns true to swallow the event. Re-enables itself if macOS disables it.
@MainActor
final class KeyTap {
    /// Tag written into `eventSourceUserData` of events we synthesize, so the tap ignores them.
    static let selfEventTag: Int64 = 0x6D61_636D_6F6A_69 // "macmoji"

    typealias Handler = @MainActor (CGEventType, CGEvent) -> Bool
    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthTimer: Timer?
    /// Called when the tap was disabled by macOS (timeout or user input).
    var onDisabled: (@MainActor () -> Void)?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Returns false if the tap could not be created (usually: no Accessibility permission).
    @discardableResult
    func start() -> Bool {
        if tap != nil { enable(); return true }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        enable()
        // Health check: catch silent disables we were not told about.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let tap = self.tap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) { self.enable() }
            }
        }
        return true
    }

    func stop() {
        healthTimer?.invalidate(); healthTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil
    }

    func enable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true to swallow the event.
    fileprivate func process(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            enable()
            onDisabled?()
            return false
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.selfEventTag { return false }
        return handler(type, event)
    }
}

/// C callback. The run loop source is on the main run loop, so this runs on the main thread.
private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let swallow: Bool = MainActor.assumeIsolated {
        let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
        return tap.process(type: type, event: event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

extension CGEvent {
    /// The characters this key event produces with the current layout (respects Shift, non-US layouts).
    var typedString: String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 16)
        keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }
}
#endif
