import HTTPClient
import XCTest

@testable import SMART

final class ServerDiscoveryTests: XCTestCase {
    func testFetchesSMARTConfigurationFromWellKnownEndpoint() async throws {
        let httpClient = MockHTTPClient()
        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        let data = try FixtureLoader.data(named: "smart-configuration")
        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
        httpClient.setResponse(for: wellKnownURL, data: data)

        let configuration = try await server.getSMARTConfiguration()
        XCTAssertEqual(configuration.authorizationEndpoint.host, "localhost")
        XCTAssertTrue(configuration.authorizationEndpoint.path.contains("/auth/authorize"))

        XCTAssertEqual(configuration.tokenEndpoint.host, "localhost")
        XCTAssertTrue(configuration.tokenEndpoint.path.contains("/auth/token"))

        XCTAssertTrue(configuration.capabilities?.contains("launch-ehr") ?? false)
        XCTAssertTrue(
            configuration.capabilities?.contains("client-confidential-symmetric") ?? false)
        XCTAssertTrue(configuration.scopesSupported?.contains("fhirUser") ?? false)

        XCTAssertEqual(httpClient.requestCount(for: wellKnownURL.path), 1)
    }

    func testSMARTConfigurationIsCachedBetweenCalls() async throws {
        let httpClient = MockHTTPClient()
        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        let data = try FixtureLoader.data(named: "smart-configuration")
        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
        httpClient.setResponse(for: wellKnownURL, data: data)

        _ = try await server.getSMARTConfiguration()
        _ = try await server.getSMARTConfiguration()

        XCTAssertEqual(httpClient.requestCount(for: wellKnownURL.path), 1)
    }

    func testForceRefreshBypassesCache() async throws {
        let httpClient = MockHTTPClient()
        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        let data = try FixtureLoader.data(named: "smart-configuration")
        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
        httpClient.setResponse(for: wellKnownURL, data: data)

        _ = try await server.getSMARTConfiguration()
        _ = try await server.getSMARTConfiguration(forceRefresh: true)

        XCTAssertEqual(httpClient.requestCount(for: wellKnownURL.path), 2)
    }

    func testConfigurationErrorsAreWrappedInSMARTClientError() async throws {
        let httpClient = MockHTTPClient()
        httpClient.shouldFail = true
        httpClient.failureError = .networkError("offline")

        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        do {
            _ = try await server.getSMARTConfiguration()
            XCTFail("Expected failure, received success")
        } catch {
            guard let smartError = error as? SMARTClientError else {
                XCTFail("Expected SMARTClientError, received: \(error)")
                return
            }
            guard case .configuration(let url, let underlying) = smartError else {
                XCTFail("Expected SMARTClientError.configuration, received: \(smartError)")
                return
            }
            XCTAssertEqual(url, SMARTConfiguration.wellKnownURL(for: baseURL))
            XCTAssertTrue(underlying is HTTPClientError)
        }
    }
}
