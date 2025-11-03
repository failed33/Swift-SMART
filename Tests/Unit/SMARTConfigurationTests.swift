import SMART
import XCTest

final class SMARTConfigurationTests: XCTestCase {
    func testDecodingSMARTConfigurationFixture() throws {
        let configuration = try FixtureLoader.decode(
            SMARTConfiguration.self, named: "smart-configuration")

        XCTAssertEqual(configuration.authorizationEndpoint.host, "localhost")
        XCTAssertTrue(configuration.authorizationEndpoint.path.contains("/auth/authorize"))

        XCTAssertEqual(configuration.tokenEndpoint.host, "localhost")
        XCTAssertTrue(configuration.tokenEndpoint.path.contains("/auth/token"))

        if let introspection = configuration.introspectionEndpoint {
            XCTAssertEqual(introspection.host, "localhost")
        }
        if let revocation = configuration.revocationEndpoint {
            XCTAssertEqual(revocation.host, "localhost")
        }
        if let jwks = configuration.jwksEndpoint {
            XCTAssertEqual(jwks.host, "localhost")
        }
        if let issuer = configuration.issuer {
            XCTAssertEqual(issuer.host, "localhost")
        }

        XCTAssertTrue(configuration.capabilities?.contains("launch-ehr") ?? false)
        XCTAssertTrue(
            configuration.capabilities?.contains("client-confidential-symmetric") ?? false)

        XCTAssertTrue(configuration.grantTypesSupported?.contains("authorization_code") ?? false)
        XCTAssertTrue(configuration.scopesSupported?.contains("openid") ?? false)
        XCTAssertTrue(configuration.scopesSupported?.contains("fhirUser") ?? false)
        XCTAssertTrue(configuration.codeChallengeMethodsSupported?.contains("S256") ?? false)

        XCTAssertTrue(
            configuration.tokenEndpointAuthMethodsSupported?.contains("client_secret_basic")
                ?? false)
        XCTAssertTrue(
            configuration.tokenEndpointAuthMethodsSupported?.contains("client_secret_post") ?? false
        )

        XCTAssertTrue(configuration.additionalFields.isEmpty)
    }

    func testAdditionalFieldsSurviveEncodingRoundTrip() throws {
        let configuration = try FixtureLoader.decode(
            SMARTConfiguration.self, named: "smart-configuration")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(configuration)
        let decoded = try JSONDecoder().decode(SMARTConfiguration.self, from: data)

        XCTAssertTrue(decoded.additionalFields.isEmpty)
    }

    func testWellKnownURLGeneration() {
        let baseURL = URL(string: "https://example.org/fhir")!
        let expected = URL(string: "https://example.org/fhir/.well-known/smart-configuration")!

        XCTAssertEqual(SMARTConfiguration.wellKnownURL(for: baseURL), expected)
    }

    func testDecodingFailsWhenRequiredEndpointsMissing() {
        let payload = """
            {
              "token_endpoint": "https://example.org/token"
            }
            """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(SMARTConfiguration.self, from: payload))
    }
}
