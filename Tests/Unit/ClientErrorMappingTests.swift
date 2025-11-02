@testable import SMART
import FHIRClient
import Foundation
import HTTPClient
import ModelsR5
import OAuth2
import XCTest

final class ClientErrorMappingTests: XCTestCase {
    func testMapsFHIRClientHTTPErrorToSMARTClientError() throws {
        let url = URL(string: "https://example.org/resource")!
        let data = try FixtureLoader.data(named: "operation-outcome")
        let outcome = try JSONDecoder().decode(ModelsR5.OperationOutcome.self, from: data)

        let urlError = URLError(.badServerResponse)
        let fhirHttpError = FHIRClientHttpError(httpClientError: .httpError(urlError), operationOutcome: outcome)
        let fhirError = FHIRClient.Error.http(fhirHttpError)

        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 400,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/fhir+json"]
        ))

        let mapped = SMARTErrorMapper.mapPublic(error: fhirError, url: url, response: response, data: data)

        guard case let .http(status, mappedURL, headers, mappedOutcome, underlying) = mapped else {
            return XCTFail("Expected SMARTClientError.http")
        }

        XCTAssertEqual(status, 400)
        XCTAssertEqual(mappedURL, url)
        XCTAssertEqual(headers["Content-Type"], "application/fhir+json")
        XCTAssertEqual(mappedOutcome?.id?.value?.string, outcome.id?.value?.string)
        XCTAssertEqual(underlying as? URLError, urlError)
    }

    func testMapsCancellationVariantsToCancelled() {
        let cancellationError = SMARTErrorMapper.mapPublic(error: CancellationError(), url: nil)
        if case .cancelled = cancellationError {
        } else {
            XCTFail("Expected cancellation to map to .cancelled")
        }

        let urlCancellation = SMARTErrorMapper.mapPublic(error: URLError(.cancelled), url: nil)
        if case .cancelled = urlCancellation {
        } else {
            XCTFail("Expected URLError.cancelled to map to .cancelled")
        }

        let oauthCancellation = SMARTErrorMapper.mapPublic(error: OAuth2Error.requestCancelled, url: nil)
        if case .cancelled = oauthCancellation {
        } else {
            XCTFail("Expected OAuth2Error.requestCancelled to map to .cancelled")
        }
    }

    func testMapsOAuthErrorToOAuthCase() {
        let endpoint = URL(string: "https://example.org/token")
        let oauthError: OAuth2Error = .invalidGrant(nil)
        let mapped = SMARTErrorMapper.mapPublic(error: oauthError, url: endpoint)

        guard case let .oauth(tokenEndpoint, underlying) = mapped else {
            return XCTFail("Expected SMARTClientError.oauth")
        }

        XCTAssertEqual(tokenEndpoint, endpoint)
        XCTAssertEqual(underlying as? OAuth2Error, oauthError)
    }

    func testMapsNetworkErrorToSMARTNetwork() {
        let underlying = HTTPClientError.networkError("offline")
        let mapped = SMARTErrorMapper.mapPublic(error: underlying, url: nil)

        guard case let .network(recovered) = mapped else {
            return XCTFail("Expected SMARTClientError.network")
        }

        XCTAssertEqual(recovered as? HTTPClientError, underlying)
    }
}


