#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Frontmost app, blocklist, secure-input checks and Electron AX wake-up.
@MainActor
final class AppContext {
    private(set) var frontmostBundleID: String?
    private(set) var frontmostPID: pid_t = 0
    private var wokenPIDs = Set<pid_t>()
    private var observer: NSObjectProtocol?
    var onAppChanged: (@MainActor () -> Void)?

    init() {
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.update(app)
                self?.onAppChanged?()
            }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        frontmostBundleID = app?.bundleIdentifier
        frontmostPID = app?.processIdentifier ?? 0
        if let app { wakeElectronAccessibility(app) }
    }

    /// Secure input is on (password field, Terminal's Secure Keyboard Entry, some password managers).
    var isSecureInputOn: Bool { IsSecureEventInputEnabled() }

    /// Whether the focused element is a secure text field.
    func focusedElementIsSecure() -> Bool {
        focusedElementSecurity() == true
    }

    /// `nil` means the focused element could not be inspected; sensitive actions should fail closed.
    func focusedElementSecurity() -> Bool? {
        guard let el = AXHelpers.focusedElement() else { return nil }
        guard case .value(let role) = AXHelpers.stringResult(el, kAXRoleAttribute) else {
            return nil
        }
        if role == "AXSecureTextField" { return true }
        switch AXHelpers.stringResult(el, kAXSubroleAttribute) {
        case .value(let subrole):
            return subrole == (kAXSecureTextFieldSubrole as String)
        case .noValue:
            return false
        case .failure:
            return nil
        }
    }

    /// Electron builds its AX tree lazily; setting AXManualAccessibility on the app element turns it on.
    private func wakeElectronAccessibility(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0, !wokenPIDs.contains(pid), Self.isElectron(app) else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result == .success { wokenPIDs.insert(pid) }
    }

    static func isElectron(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        let fw = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: fw.path)
    }
}

enum AXHelpers {
    enum StringResult {
        case value(String)
        case noValue
        case failure
    }

    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.15)
        return el
    }()

    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let el = value as! AXUIElement // swiftlint:disable:this force_cast
        AXUIElementSetMessagingTimeout(el, 0.15)
        return el
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        guard case .value(let value) = stringResult(el, attr) else { return nil }
        return value
    }

    static func stringResult(_ el: AXUIElement, _ attr: String) -> StringResult {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        if result == .noValue || result == .attributeUnsupported { return .noValue }
        guard result == .success, let string = value as? String else { return .failure }
        return .value(string)
    }

    static func axValue(_ el: AXUIElement, _ attr: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue) // swiftlint:disable:this force_cast
    }
}
#endif
