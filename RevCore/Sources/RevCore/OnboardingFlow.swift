/// Portable step sequencing for the first-run onboarding window. The app supplies live facts
/// (is Accessibility granted?) and renders the current step.
public struct OnboardingFlow: Equatable, Sendable {
    public enum Step: Int, CaseIterable, Sendable {
        case skinTone, launchAtLogin, accessibility, finish

        public var title: String {
            switch self {
            case .skinTone: return "Default skin tone"
            case .launchAtLogin: return "Launch at login"
            case .accessibility: return "Accessibility permission"
            case .finish: return "You're all set"
            }
        }
    }

    /// UserDefaults key for the "onboarding finished" flag.
    public static let completedDefaultsKey = "onboardingCompleted"

    public let steps: [Step]
    public private(set) var index: Int = 0

    public init(steps: [Step] = Step.allCases) {
        precondition(!steps.isEmpty)
        self.steps = steps
    }

    public var current: Step { steps[index] }
    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == steps.count - 1 }
    /// 1-based position for "Step 2 of 4".
    public var position: Int { index + 1 }

    public var canGoBack: Bool { !isFirst }

    /// Next is blocked on the Accessibility step until access is granted.
    public func canGoNext(accessibilityGranted: Bool) -> Bool {
        if isLast { return false }
        if current == .accessibility { return accessibilityGranted }
        return true
    }

    @discardableResult
    public mutating func next(accessibilityGranted: Bool) -> Bool {
        guard canGoNext(accessibilityGranted: accessibilityGranted) else { return false }
        index += 1
        return true
    }

    @discardableResult
    public mutating func back() -> Bool {
        guard canGoBack else { return false }
        index -= 1
        return true
    }

    /// Call whenever the trust state is polled; moves on by itself once access appears.
    @discardableResult
    public mutating func accessibilityChanged(granted: Bool) -> Bool {
        guard current == .accessibility, granted else { return false }
        return next(accessibilityGranted: true)
    }
}

/// What the app should do at launch.
public enum LaunchDecision: Equatable, Sendable {
    /// Show onboarding; do not start the event tap yet.
    case onboarding
    /// Start running (event tap) now.
    case run
    /// Onboarding done but Accessibility missing (e.g. revoked): show the permission prompt.
    case permissionPrompt

    public static func decide(onboardingCompleted: Bool, accessibilityGranted: Bool) -> LaunchDecision {
        if !onboardingCompleted { return .onboarding }
        return accessibilityGranted ? .run : .permissionPrompt
    }
}
