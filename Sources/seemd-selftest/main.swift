import Foundation
import SeemdCore

// Aggregated self-test suite. Each story appends its cases to `allCases`.
// Run with: swift run seemd-selftest
var allCases: [TestCase] = []

allCases += [
    TestCase("scaffold/core-version") { t in
        t.expectEqual(SeemdCore.version, "0.1.0")
    }
]

// US-002+ suites are appended below as features land.
allCases += scaffoldSmokeCases()

exit(runSelfTests(allCases))
