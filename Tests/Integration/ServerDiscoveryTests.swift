@testable import SMART
import XCTest

final class ServerDiscoveryTests: XCTestCase {
    func testFetchesSMARTConfigurationFromWellKnownEndpoint() throws {
        let httpClient = MockHTTPClient()
        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        let data = try FixtureLoader.data(named: "smart-configuration")
        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
        httpClient.setResponse(for: wellKnownURL, data: data)

        let expectation = expectation(description: "SMART configuration fetch")

        server.getSMARTConfiguration { result in
            switch result {
            case .success(let configuration):
                XCTAssertEqual(configuration.authorizationEndpoint.host, "localhost")
                XCTAssertTrue(configuration.authorizationEndpoint.path.contains("/auth/authorize"))

                XCTAssertEqual(configuration.tokenEndpoint.host, "localhost")
                XCTAssertTrue(configuration.tokenEndpoint.path.contains("/auth/token"))

                XCTAssertTrue(configuration.capabilities?.contains("launch-ehr") ?? false)
                XCTAssertTrue(configuration.capabilities?.contains("client-confidential-symmetric") ?? false)
                XCTAssertTrue(configuration.scopesSupported?.contains("fhirUser") ?? false)
            case .failure(let error):
                XCTFail("Expected success, received error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)
        XCTAssertEqual(httpClient.requestCount(for: wellKnownURL.path), 1)
    }

    func testSMARTConfigurationIsCachedBetweenCalls() throws {
        let httpClient = MockHTTPClient()
        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        let data = try FixtureLoader.data(named: "smart-configuration")
        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
        httpClient.setResponse(for: wellKnownURL, data: data)

        let firstFetch = expectation(description: "First configuration fetch")
        server.getSMARTConfiguration { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, received error: \(error)")
            }
            firstFetch.fulfill()
        }
        wait(for: [firstFetch], timeout: 2)

        let secondFetch = expectation(description: "Second configuration fetch (cached)")
        server.getSMARTConfiguration { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, received error: \(error)")
            }
            secondFetch.fulfill()
        }
        wait(for: [secondFetch], timeout: 2)

        XCTAssertEqual(httpClient.requestCount(for: wellKnownURL.path), 1)
    }

    func testForceRefreshBypassesCache() throws {
        let httpClient = MockHTTPClient()
        let baseURL = URL(string: "https://example.org/fhir")!
        let server = Server(baseURL: baseURL, httpClient: httpClient)

        let data = try FixtureLoader.data(named: "smart-configuration")
        let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
        httpClient.setResponse(for: wellKnownURL, data: data)

        let firstFetch = expectation(description: "Initial configuration fetch")
        server.getSMARTConfiguration { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, received error: \(error)")
            }
            firstFetch.fulfill()
        }
        wait(for: [firstFetch], timeout: 2)

        let secondFetch = expectation(description: "Forced refresh configuration fetch")
        server.getSMARTConfiguration(forceRefresh: true) { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, received error: \(error)")
            }
            secondFetch.fulfill()
        }
        wait(for: [secondFetch], timeout: 2)

        XCTAssertEqual(httpClient.requestCount(for: wellKnownURL.path), 2)
    }
}

