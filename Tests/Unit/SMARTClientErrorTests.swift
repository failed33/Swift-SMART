@testable import SMART
import Foundation
import ModelsR5
import OAuth2
import XCTest

final class SMARTClientErrorTests: XCTestCase {
    func testConfigurationErrorMaintainsDetails() {
        let url = URL(string: "https://example.org/config")!
        let underlying = NSError(domain: "Test", code: 42)

        let error = SMARTClientError.configuration(url: url, underlying: underlying)

        guard case let .configuration(recoveredURL, recoveredUnderlying) = error else {
            return XCTFail("Expected configuration case")
        }
        XCTAssertEqual(recoveredURL, url)
        XCTAssertEqual(recoveredUnderlying as NSError, underlying)

        XCTAssertEqual(
            error.errorDescription,
            "Configuration error for https://example.org/config: The operation couldn’t be completed. (Test error 42.)"
        )
        XCTAssertEqual(error.errorCode, 1)

        let userInfo = error.errorUserInfo
        XCTAssertEqual(userInfo[NSURLErrorKey] as? URL, url)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? NSError, underlying)
    }

    func testOAuthErrorMaintainsDetails() {
        let endpoint = URL(string: "https://example.org/token")!
        let oauthError: OAuth2Error = .invalidGrant(nil)
        let error = SMARTClientError.oauth(tokenEndpoint: endpoint, underlying: oauthError)

        guard case let .oauth(recoveredEndpoint, recoveredUnderlying) = error else {
            return XCTFail("Expected oauth case")
        }
        XCTAssertEqual(recoveredEndpoint, endpoint)
        XCTAssertEqual(recoveredUnderlying as? OAuth2Error, oauthError)
        XCTAssertEqual(error.errorDescription, oauthError.localizedDescription)
        XCTAssertEqual(error.errorCode, 2)

        let userInfo = error.errorUserInfo
        XCTAssertEqual(userInfo[NSURLErrorKey] as? URL, endpoint)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? OAuth2Error, oauthError)
    }

    func testHTTPErrorEncodesOperationOutcome() throws {
        let url = URL(string: "https://example.org/resource")!
        let headers = ["Retry-After": "120", "Content-Type": "application/fhir+json"]
        let underlying = URLError(.userAuthenticationRequired)
        let data = try FixtureLoader.data(named: "operation-outcome")
        let outcome = try JSONDecoder().decode(ModelsR5.OperationOutcome.self, from: data)

        let error = SMARTClientError.http(
            status: 401,
            url: url,
            headers: headers,
            outcome: outcome,
            underlying: underlying
        )

        guard case let .http(status, recoveredURL, recoveredHeaders, recoveredOutcome, recoveredUnderlying) = error else {
            return XCTFail("Expected http case")
        }

        XCTAssertEqual(status, 401)
        XCTAssertEqual(recoveredURL, url)
        XCTAssertEqual(recoveredHeaders, headers)
        XCTAssertEqual(recoveredUnderlying as? URLError, underlying)
        XCTAssertEqual(recoveredOutcome?.id?.value?.string, outcome.id?.value?.string)
        XCTAssertEqual(error.errorCode, 3)

        let userInfo = error.errorUserInfo
        XCTAssertEqual(userInfo[NSURLErrorKey] as? URL, url)
        XCTAssertEqual(userInfo["HTTPHeaders"] as? [String: String], headers)
        XCTAssertEqual(userInfo[NSUnderlyingErrorKey] as? URLError, underlying)

        let storedOutcomeData = try XCTUnwrap(userInfo["OperationOutcome"] as? Data)
        let decodedOutcome = try JSONDecoder().decode(ModelsR5.OperationOutcome.self, from: storedOutcomeData)
        XCTAssertEqual(decodedOutcome.id?.value?.string, outcome.id?.value?.string)
    }

    func testDecodingErrorMaintainsDetails() {
        let url = URL(string: "https://example.org/decode")!
        let underlying = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid"))
        let error = SMARTClientError.decoding(url: url, underlying: underlying, bodySnippet: "{...}")

        guard case let .decoding(recoveredURL, recoveredUnderlying, snippet) = error else {
            return XCTFail("Expected decoding case")
        }

        XCTAssertEqual(recoveredURL, url)
        XCTAssertNotNil(recoveredUnderlying)
        XCTAssertEqual(snippet, "{...}")
        XCTAssertEqual(error.errorCode, 4)

        let userInfo = error.errorUserInfo
        XCTAssertEqual(userInfo[NSURLErrorKey] as? URL, url)
        XCTAssertEqual(userInfo["BodySnippet"] as? String, "{...}")
        XCTAssertNotNil(userInfo[NSUnderlyingErrorKey])
    }

    func testCancelledErrorProvidesUserInfo() {
        let error = SMARTClientError.cancelled

        if case .cancelled = error {
            XCTAssertEqual(error.errorCode, 5)
            XCTAssertEqual(error.errorDescription, "Operation was cancelled")
            XCTAssertTrue(error.errorUserInfo.isEmpty)
        } else {
            XCTFail("Expected cancelled case")
        }
    }

    func testRateLimitedMaintainsRetryAfter() throws {
        let retryDate = Date().addingTimeInterval(60)
        let url = URL(string: "https://example.org/rate")!
        let error = SMARTClientError.rateLimited(retryAfter: retryDate, url: url)

        guard case let .rateLimited(recoveredDate, recoveredURL) = error else {
            return XCTFail("Expected rateLimited case")
        }

        let resolvedDate = try XCTUnwrap(recoveredDate)
        XCTAssertEqual(resolvedDate.timeIntervalSince1970, retryDate.timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(recoveredURL, url)
        XCTAssertEqual(error.errorCode, 6)

        let userInfo = error.errorUserInfo
        XCTAssertEqual(userInfo[NSURLErrorKey] as? URL, url)
        let storedDate = try XCTUnwrap(userInfo["RetryAfter"] as? Date)
        XCTAssertEqual(storedDate.timeIntervalSince1970, retryDate.timeIntervalSince1970, accuracy: 0.5)
    }

    func testNetworkAndOtherMaintainUnderlying() {
        let networkUnderlying = URLError(.notConnectedToInternet)
        let networkError = SMARTClientError.network(underlying: networkUnderlying)
        guard case let .network(recoveredNetworkError) = networkError else {
            return XCTFail("Expected network case")
        }
        XCTAssertEqual(recoveredNetworkError as? URLError, networkUnderlying)
        XCTAssertEqual(networkError.errorCode, 7)
        XCTAssertEqual(networkError.errorUserInfo[NSUnderlyingErrorKey] as? URLError, networkUnderlying)

        let otherUnderlying = NSError(domain: "Other", code: 7)
        let otherError = SMARTClientError.other(underlying: otherUnderlying)
        guard case let .other(recoveredOtherError) = otherError else {
            return XCTFail("Expected other case")
        }
        XCTAssertEqual(recoveredOtherError as NSError, otherUnderlying)
        XCTAssertEqual(otherError.errorCode, 8)
        XCTAssertEqual(otherError.errorUserInfo[NSUnderlyingErrorKey] as? NSError, otherUnderlying)
    }
}


