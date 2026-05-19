import Foundation

// Per-feature self-test case providers. Each story adds a `*Cases()` function
// here (or in its own file) and wires it into Sources/seemd-selftest/main.swift.

public func scaffoldSmokeCases() -> [TestCase] {
    [
        TestCase("scaffold/harness-detects-failure") { t in
            let inner = TestContext()
            inner.expect(false, "intentional")
            t.expectEqual(inner.failures.count, 1, "harness must record failures")
        },
        TestCase("scaffold/harness-passes-truth") { t in
            let inner = TestContext()
            inner.expect(true, "should not record")
            t.expectEqual(inner.failures.count, 0)
        }
    ]
}
