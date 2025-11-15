import Foundation
import XCTest

@testable import SMART

@MainActor
final class AuthPerformanceTests: XCTestCase {
    func testPKCEGenerationPerformance() {
        measure {
            _ = PKCE.generate(length: 96)
        }
    }

    func testScopeNormalizationPerformance() {
        let server = Server(baseURL: URL(string: "https://example.org/fhir")!)
        let auth = Auth(
            type: .codeGrant,
            server: server,
            aud: server.aud,
            initialLogger: nil,
            settings: nil,
            uiHandler: TestAuthUIHandler()
        )
        var properties = SMARTAuthProperties()
        properties.granularity = .patientSelectNative

        measure {
            _ = auth.updatedScope(
                from: "patient/*.read user/*.write offline_access",
                properties: properties
            )
        }
    }
}
