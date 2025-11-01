@testable import SMART
import XCTest

final class ScopeTests: XCTestCase {
    private func makeAuth() -> Auth {
        let server = Server(baseURL: URL(string: "https://example.org/fhir")!)
        return Auth(type: .codeGrant, server: server, settings: nil)
    }

    func testNormalizationAppliesSMARTv2Requirements() {
        let auth = makeAuth()
        var properties = SMARTAuthProperties()
        properties.granularity = .tokenOnly

        let scope = auth.updatedScope(
            from: "patient/*.read user/*.write offline_access",
            properties: properties
        )

        let components = Set(scope.split(separator: " ").map(String.init))
        XCTAssertTrue(components.contains("openid"))
        XCTAssertTrue(components.contains("fhirUser"))
        XCTAssertTrue(components.contains("patient/*.rs"))
        XCTAssertTrue(components.contains("user/*.cruds"))
        XCTAssertTrue(components.contains("offline_access"))
        XCTAssertFalse(components.contains("profile"))
    }

    func testNormalizationAddsLaunchScopesForGranularity() {
        let auth = makeAuth()

        var launchProperties = SMARTAuthProperties()
        launchProperties.granularity = .launchContext
        let launchScope = auth.updatedScope(from: "openid fhirUser", properties: launchProperties)
        XCTAssertTrue(launchScope.split(separator: " ").contains("launch"))

        var patientProperties = SMARTAuthProperties()
        patientProperties.granularity = .patientSelectNative
        let patientScope = auth.updatedScope(from: "openid fhirUser", properties: patientProperties)
        XCTAssertTrue(patientScope.split(separator: " ").contains("launch/patient"))
    }

    func testNormalizationProvidesDefaultScopesWhenMissing() {
        let auth = makeAuth()

        var properties = SMARTAuthProperties()
        properties.granularity = .tokenOnly

        let scope = auth.updatedScope(from: nil, properties: properties)
        let components = Set(scope.split(separator: " ").map(String.init))

        XCTAssertTrue(components.contains("user/*.cruds"))
        XCTAssertTrue(components.contains("openid"))
        XCTAssertTrue(components.contains("fhirUser"))
        XCTAssertFalse(components.contains("profile"))
    }
}

