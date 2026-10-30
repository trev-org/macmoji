import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)
}

/// Detects a short modifier-only chord without interfering with normal modified key shortcuts.
public struct ModifierChordStateMachine: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case trigger
    }

    private enum State: Equatable, Sendable {
        case idle
        case tracking(startedAt: TimeInterval, reachedExactChord: Bool)
        case cancelled
    }

    public var chord: ShortcutModifiers
    public var maximumHoldDuration: TimeInterval
    private var state: State = .idle

    public init(
        chord: ShortcutModifiers,
        maximumHoldDuration: TimeInterval = 0.5
    ) {
        precondition(!chord.isEmpty)
        precondition(maximumHoldDuration > 0)
        self.chord = chord
        self.maximumHoldDuration = maximumHoldDuration
    }

    @discardableResult
    public mutating func flagsChanged(
        modifiers: ShortcutModifiers,
        at timestamp: TimeInterval
    ) -> Action {
        switch state {
        case .idle:
            guard !modifiers.isEmpty else { return .none }
            guard modifiers.isSubset(of: chord) else {
                state = .cancelled
                return .none
            }
            state = .tracking(
                startedAt: timestamp,
                reachedExactChord: modifiers == chord
            )
            return .none

        case .tracking(let startedAt, let reachedExactChord):
            if modifiers.isEmpty {
                state = .idle
                let duration = max(0, timestamp - startedAt)
                return reachedExactChord && duration < maximumHoldDuration ? .trigger : .none
            }
            guard modifiers.isSubset(of: chord) else {
                state = .cancelled
                return .none
            }
            state = .tracking(
                startedAt: startedAt,
                reachedExactChord: reachedExactChord || modifiers == chord
            )
            return .none

        case .cancelled:
            if modifiers.isEmpty { state = .idle }
            return .none
        }
    }

    /// Call for any non-modifier key or mouse event while a chord may be in progress.
    public mutating func interrupt() {
        if state != .idle { state = .cancelled }
    }

    public mutating func reset(chord: ShortcutModifiers? = nil) {
        if let chord {
            precondition(!chord.isEmpty)
            self.chord = chord
        }
        state = .idle
    }
}
