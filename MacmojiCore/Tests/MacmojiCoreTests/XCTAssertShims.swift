// Thin XCTest-style assertion helpers on top of Swift Testing, so the suite runs with
// just the Command Line Tools (which ship Swift Testing but not XCTest) as well as Xcode.
import Testing

func XCTAssertTrue(_ v: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                   sourceLocation: SourceLocation = #_sourceLocation) rethrows {
    let ok = try v()
    if !ok { Issue.record("XCTAssertTrue failed \(message())", sourceLocation: sourceLocation) }
}

func XCTAssertFalse(_ v: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                    sourceLocation: SourceLocation = #_sourceLocation) rethrows {
    let ok = try v()
    if ok { Issue.record("XCTAssertFalse failed \(message())", sourceLocation: sourceLocation) }
}

func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                  _ message: @autoclosure () -> String = "",
                                  sourceLocation: SourceLocation = #_sourceLocation) rethrows {
    let x = try a(), y = try b()
    if x != y { Issue.record("XCTAssertEqual failed: (\(x)) != (\(y)) \(message())", sourceLocation: sourceLocation) }
}

func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                      accuracy: T, _ message: @autoclosure () -> String = "",
                                      sourceLocation: SourceLocation = #_sourceLocation) rethrows {
    let x = try a(), y = try b()
    if abs(x - y) > accuracy { Issue.record("XCTAssertEqual failed: (\(x)) != (\(y)) ± \(accuracy) \(message())", sourceLocation: sourceLocation) }
}

func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "",
                                         sourceLocation: SourceLocation = #_sourceLocation) rethrows {
    let x = try a(), y = try b()
    if !(x > y) { Issue.record("XCTAssertGreaterThan failed: (\(x)) <= (\(y)) \(message())", sourceLocation: sourceLocation) }
}

func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                             _ message: @autoclosure () -> String = "",
                                             sourceLocation: SourceLocation = #_sourceLocation) rethrows {
    let x = try a(), y = try b()
    if !(x <= y) { Issue.record("XCTAssertLessThanOrEqual failed: (\(x)) > (\(y)) \(message())", sourceLocation: sourceLocation) }
}
