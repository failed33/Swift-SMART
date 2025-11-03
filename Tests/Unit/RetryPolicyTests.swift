@testable import HTTPClientLive
import Foundation
import HTTPClient
import XCTest

final class RetryPolicyTests: XCTestCase {
    func testDirectiveForResponseHonorsRetryAfterSeconds() {
        let policy = RetryPolicy(maxRetries: 3, retryAfterRetries: 2)
        let directive = policy.directiveForResponse(
            statusCode: HTTPStatusCode.serviceUnavailable.rawValue,
            method: HTTPMethod.get.rawValue,
            retryAfterHeader: "5",
            attempt: 0
        )

        XCTAssertNotNil(directive)
        XCTAssertEqual(directive?.reason, .retryAfter)
        XCTAssertEqual(directive?.delay, 5)
    }

    func testDirectiveForResponseParsesHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        let futureDate = Date().addingTimeInterval(60)
        let header = formatter.string(from: futureDate)

        let policy = RetryPolicy(maxRetries: 3, retryAfterRetries: 2)
        let directive = policy.directiveForResponse(
            statusCode: HTTPStatusCode.serviceUnavailable.rawValue,
            method: HTTPMethod.get.rawValue,
            retryAfterHeader: header,
            attempt: 0
        )

        XCTAssertNotNil(directive)
        XCTAssertEqual(directive?.reason, .retryAfter)
        XCTAssertEqual(directive?.delay ?? 0, futureDate.timeIntervalSinceNow, accuracy: 1)
    }

    func testDirectiveRequiresRetriesRemaining() {
        let policy = RetryPolicy(maxRetries: 1)
        let directive = policy.directiveForResponse(
            statusCode: HTTPStatusCode.serviceUnavailable.rawValue,
            method: HTTPMethod.get.rawValue,
            retryAfterHeader: nil,
            attempt: 1
        )

        XCTAssertNil(directive)
    }

    func testTransientStatusUsesBackoff() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 0.5)
        let directive = policy.directiveForResponse(
            statusCode: HTTPStatusCode.serviceUnavailable.rawValue,
            method: HTTPMethod.get.rawValue,
            retryAfterHeader: nil,
            attempt: 1
        )

        XCTAssertNotNil(directive)
        XCTAssertEqual(directive?.reason, .transient)
        XCTAssertEqual(directive?.delay, 1.0)
    }

    func testDirectiveDisallowsNonIdempotentMethod() {
        let policy = RetryPolicy(maxRetries: 3)
        let directive = policy.directiveForResponse(
            statusCode: HTTPStatusCode.serviceUnavailable.rawValue,
            method: HTTPMethod.post.rawValue,
            retryAfterHeader: nil,
            attempt: 0
        )

        XCTAssertNil(directive)
    }

    func testDirectiveForErrorRespectsMaxRetries() {
        let policy = RetryPolicy(maxRetries: 2, baseDelay: 0.25)
        let urlError = URLError(.timedOut)
        let directive = policy.directiveForError(urlError, method: HTTPMethod.get.rawValue, attempt: 1)

        XCTAssertNotNil(directive)
        XCTAssertEqual(directive?.reason, .transient)
        XCTAssertEqual(directive?.delay, 0.5)

        let none = policy.directiveForError(urlError, method: HTTPMethod.get.rawValue, attempt: 2)
        XCTAssertNil(none)
    }

    func testJitterAndMaxBackoffAppliedDeterministically() throws {
        let policy = RetryPolicy(
            maxRetries: 4,
            baseDelay: 1,
            maxBackoff: 1.5,
            jitter: 0...0.1,
            randomGenerator: { _ in 0.05 }
        )

        let directive = policy.directiveForResponse(
            statusCode: HTTPStatusCode.serviceUnavailable.rawValue,
            method: HTTPMethod.get.rawValue,
            retryAfterHeader: nil,
            attempt: 2
        )

        let delay = try XCTUnwrap(directive?.delay)
        XCTAssertEqual(delay, 1.575, accuracy: 0.0001)
    }
}


