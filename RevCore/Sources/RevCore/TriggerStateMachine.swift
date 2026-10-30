/// Pure state machine that turns typed characters into picker actions. No AppKit.
///
/// The event tap feeds it every character the user types (after the tap decided the key is not
/// consumed). It never swallows ':' or letters; it only reports what the UI should do.
public struct TriggerStateMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        /// ':' typed at a boundary, nothing after it yet.
        case armed
        /// ':' plus `query` typed.
        case querying(String)
    }

    public enum Input: Equatable, Sendable {
        case character(Character)
        case backspace
        /// Mouse click, app switch, focus change, arrow keys with no picker, modifier shortcuts, etc.
        case reset
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Show or update the picker for this query.
        case show(query: String)
        /// Hide the picker if visible.
        case hide
        /// `:name:` typed and `name` is an exact shortcode: delete `deleteCount` chars and insert.
        case autoReplace(name: String, deleteCount: Int)
    }

    public private(set) var state: State = .idle
    /// Last character typed while idle (nil = start of text / unknown context).
    public private(set) var previous: Character?
    /// Returns true if `name` is an exact shortcode (used for `:name:` auto-replace).
    public var isExactName: @Sendable (String) -> Bool

    public init(isExactName: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.isExactName = isExactName
    }

    public var currentQuery: String? {
        if case .querying(let q) = state { return q }
        return nil
    }

    /// Whether the picker should currently be visible.
    public var isPickerVisible: Bool {
        (currentQuery?.count ?? 0) >= ShortcodeRules.minimumQueryLength
    }

    /// Number of characters (":" + query) to delete when committing a selection.
    public var deleteCountForCommit: Int { (currentQuery?.count ?? 0) + 1 }

    @discardableResult
    public mutating func handle(_ input: Input) -> Action {
        let wasVisible = isPickerVisible
        switch input {
        case .reset:
            state = .idle
            previous = nil
            return wasVisible ? .hide : .none

        case .backspace:
            switch state {
            case .idle:
                previous = nil // unknown what is now before the caret; treat as boundary-unknown
                return .none
            case .armed:
                state = .idle
                previous = nil
                return .none
            case .querying(let q):
                let shorter = String(q.dropLast())
                state = shorter.isEmpty ? .armed : .querying(shorter)
                if isPickerVisible { return .show(query: shorter) }
                return wasVisible ? .hide : .none
            }

        case .character(let c):
            switch state {
            case .idle:
                if c == ":" && ShortcodeRules.isBoundary(previous) {
                    state = .armed
                }
                previous = c
                return .none
            case .armed:
                if ShortcodeRules.cancelsRightAfterColon(c) {
                    state = .idle
                    previous = c
                    return .none
                }
                state = .querying(String(c))
                return .none
            case .querying(let q):
                if ShortcodeRules.isShortcodeChar(c) {
                    let longer = q + String(c)
                    state = .querying(longer)
                    return isPickerVisible ? .show(query: longer) : .none
                }
                state = .idle
                previous = c
                if c == ":" && isExactName(q) {
                    return .autoReplace(name: q, deleteCount: q.count + 2)
                }
                return wasVisible ? .hide : .none
            }
        }
    }

    /// Call after an emoji was inserted (from the picker or auto-replace).
    public mutating func didCommit() {
        state = .idle
        previous = "\u{FFFC}" // non-boundary placeholder: ':' right after an emoji does not arm
    }

    /// Call when the user dismisses the picker with Esc: the text stays, stop tracking it.
    public mutating func cancel() {
        state = .idle
        previous = "\u{FFFC}"
    }
}
