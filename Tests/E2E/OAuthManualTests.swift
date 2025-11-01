import XCTest

final class OAuthManualTests: XCTestCase {
    func testManualOAuthFlowChecklist() throws {
        let environment = ProcessInfo.processInfo.environment

        guard environment["RUN_MANUAL_OAUTH"] == "1" else {
            throw XCTSkip("Manual OAuth tests disabled. Set RUN_MANUAL_OAUTH=1 to enable.")
        }

        guard environment["SMART_LAUNCHER_URL"] != nil else {
            XCTFail("SMART_LAUNCHER_URL must be set when RUN_MANUAL_OAUTH=1")
            return
        }

        let confirmation = environment["SMART_MANUAL_AUTH_CONFIRMED"]
        XCTAssertEqual(
            confirmation,
            "1",
            "Set SMART_MANUAL_AUTH_CONFIRMED=1 after completing the documented manual OAuth checklist."
        )
    }
}

