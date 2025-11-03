@testable import SMART
import XCTest

final class AuthPerformanceTests: XCTestCase {
    func testPKCEGenerationPerformance() {
        measure {
            _ = PKCE.generate(length: 96)
        }
    }

    func testScopeNormalizationPerformance() {
        let server = Server(baseURL: URL(string: "https://example.org/fhir")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)
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

