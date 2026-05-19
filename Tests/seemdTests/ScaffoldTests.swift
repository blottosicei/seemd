import XCTest
@testable import seemd

final class ScaffoldTests: XCTestCase {
    func testAppTypeExists() {
        // Smoke test: the app entrypoint type is reachable from the test target.
        XCTAssertNotNil(SeemdApp.self)
    }
}
