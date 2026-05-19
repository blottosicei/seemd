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

// Per-feature suites (appended as stories land).
allCases += scaffoldSmokeCases()
allCases += parsingCases()        // US-002
allCases += renderCases()         // US-003
allCases += highlightCases()      // US-004
allCases += liveReloadCases()     // US-006
allCases += themeCases()          // US-007
allCases += searchZoomCases()     // US-009 (pure logic)
allCases += bookmarkCases()       // US-005 (bookmark helper)

exit(runSelfTests(allCases))
