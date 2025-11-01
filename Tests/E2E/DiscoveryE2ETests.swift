import SMART
import XCTest

final class DiscoveryE2ETests: XCTestCase {
    func testSMARTDiscoveryAgainstLauncher() async throws {
        guard let launcherURLString = ProcessInfo.processInfo.environment["SMART_LAUNCHER_URL"],
              let launcherURL = URL(string: launcherURLString) else {
            throw XCTSkip("SMART_LAUNCHER_URL not configured; skipping E2E discovery test")
        }

        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: launcherURL)
        let (data, response) = try await URLSession.shared.data(from: wellKnownURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Expected HTTPURLResponse")
            return
        }

        XCTAssertTrue((200..<300).contains(httpResponse.statusCode), "Discovery request failed with status \(httpResponse.statusCode)")

        let configuration = try JSONDecoder().decode(SMARTConfiguration.self, from: data)
        XCTAssertFalse(configuration.authorizationEndpoint.absoluteString.isEmpty)
        XCTAssertFalse(configuration.tokenEndpoint.absoluteString.isEmpty)
    }
}

