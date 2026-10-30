import Foundation
import Testing
@testable import RevCore

@Suite struct OnboardingFlowTests {
    @Test func testOrderAndBounds() {
        var f = OnboardingFlow()
        XCTAssertEqual(f.steps, [.skinTone, .launchAtLogin, .accessibility, .finish])
        XCTAssertEqual(f.current, .skinTone)
        XCTAssertFalse(f.canGoBack)
        XCTAssertFalse(f.back())
        XCTAssertTrue(f.next(accessibilityGranted: false))
        XCTAssertEqual(f.current, .launchAtLogin)
        XCTAssertTrue(f.back())
        XCTAssertEqual(f.current, .skinTone)
    }

    @Test func testAccessibilityBlocksNextUntilGranted() {
        var f = OnboardingFlow()
        f.next(accessibilityGranted: false); f.next(accessibilityGranted: false)
        XCTAssertEqual(f.current, .accessibility)
        XCTAssertFalse(f.canGoNext(accessibilityGranted: false))
        XCTAssertFalse(f.next(accessibilityGranted: false))
        XCTAssertEqual(f.current, .accessibility)
        XCTAssertTrue(f.canGoNext(accessibilityGranted: true))
    }

    @Test func testAutoAdvanceOnGrantOnlyOnAccessibilityStep() {
        var f = OnboardingFlow()
        XCTAssertFalse(f.accessibilityChanged(granted: true)) // on skin tone: no jump
        XCTAssertEqual(f.current, .skinTone)
        f.next(accessibilityGranted: true); f.next(accessibilityGranted: true)
        XCTAssertFalse(f.accessibilityChanged(granted: false))
        XCTAssertTrue(f.accessibilityChanged(granted: true))
        XCTAssertEqual(f.current, .finish)
        XCTAssertTrue(f.isLast)
        XCTAssertFalse(f.canGoNext(accessibilityGranted: true))
        XCTAssertEqual(f.position, 4)
    }

    @Test func testBackFromFinish() {
        var f = OnboardingFlow()
        for _ in 0..<3 { f.next(accessibilityGranted: true) }
        XCTAssertTrue(f.back())
        XCTAssertEqual(f.current, .accessibility)
    }

    @Test func testLaunchDecision() {
        XCTAssertEqual(LaunchDecision.decide(onboardingCompleted: false, accessibilityGranted: true), .onboarding)
        XCTAssertEqual(LaunchDecision.decide(onboardingCompleted: false, accessibilityGranted: false), .onboarding)
        XCTAssertEqual(LaunchDecision.decide(onboardingCompleted: true, accessibilityGranted: true), .run)
        XCTAssertEqual(LaunchDecision.decide(onboardingCompleted: true, accessibilityGranted: false), .permissionPrompt)
    }
}
