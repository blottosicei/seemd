import Foundation

/// Minimal XCTest-free assertion harness.
///
/// Command Line Tools (no full Xcode) cannot run `swift test` (XCTest SDK
/// platform path is unavailable). Instead, logic is verified by the
/// `seemd-selftest` executable which registers `TestCase`s and runs them.
public struct TestFailure: Error, CustomStringConvertible {
    public let message: String
    public let file: StaticString
    public let line: UInt
    public var description: String { "\(file):\(line): \(message)" }
}

public final class TestContext {
    public private(set) var failures: [TestFailure] = []

    public func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                        file: StaticString = #file, line: UInt = #line) {
        if !condition {
            failures.append(TestFailure(message: message(), file: file, line: line))
        }
    }

    public func expectEqual<T: Equatable>(_ a: T, _ b: T,
                                          _ message: @autoclosure () -> String = "",
                                          file: StaticString = #file, line: UInt = #line) {
        if a != b {
            let m = message()
            let detail = "expected \(b), got \(a)" + (m.isEmpty ? "" : " — \(m)")
            failures.append(TestFailure(message: detail, file: file, line: line))
        }
    }
}

public struct TestCase {
    public let name: String
    public let run: (TestContext) -> Void
    public init(_ name: String, _ run: @escaping (TestContext) -> Void) {
        self.name = name
        self.run = run
    }
}

/// Runs all cases, prints a report, returns process exit code (0 = pass).
public func runSelfTests(_ cases: [TestCase]) -> Int32 {
    var totalFailures = 0
    for c in cases {
        let ctx = TestContext()
        c.run(ctx)
        if ctx.failures.isEmpty {
            print("✓ \(c.name)")
        } else {
            totalFailures += ctx.failures.count
            print("✗ \(c.name)")
            for f in ctx.failures { print("    \(f)") }
        }
    }
    print("---")
    if totalFailures == 0 {
        print("PASS — \(cases.count) cases")
        return 0
    } else {
        print("FAIL — \(totalFailures) failure(s) across \(cases.count) cases")
        return 1
    }
}
