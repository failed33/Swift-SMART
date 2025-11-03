@testable import SMART
import XCTest

final class BearerChallengeTests: XCTestCase {
    func testParseWWWAuthenticateParsesBearerChallenge() {
        let header = "Bearer error=\"invalid_token\", error_description=\"Token expired\", error_uri=\"https://example.org/docs\""

        let challenge = parseWWWAuthenticate(header)

        XCTAssertNotNil(challenge)
        XCTAssertEqual(challenge?.scheme, "Bearer")
        XCTAssertEqual(challenge?.parameters["error"], "invalid_token")
        XCTAssertEqual(challenge?.parameters["error_description"], "Token expired")
        XCTAssertEqual(challenge?.parameters["error_uri"], "https://example.org/docs")
        XCTAssertEqual(challenge?.error, "invalid_token")
        XCTAssertEqual(challenge?.errorDescription, "Token expired")
        XCTAssertEqual(challenge?.errorURI, "https://example.org/docs")
        XCTAssertEqual(challenge?.value(for: "error"), "invalid_token")
    }

    func testParseWWWAuthenticateHandlesSchemeOnly() {
        let challenge = parseWWWAuthenticate("Bearer")

        XCTAssertNotNil(challenge)
        XCTAssertEqual(challenge?.scheme, "Bearer")
        XCTAssertTrue(challenge?.parameters.isEmpty ?? false)
    }

    func testParseWWWAuthenticateReturnsNilForEmptyHeaders() {
        XCTAssertNil(parseWWWAuthenticate(nil))
        XCTAssertNil(parseWWWAuthenticate(""))
        XCTAssertNil(parseWWWAuthenticate("   "))
    }

    func testParseWWWAuthenticateReturnsNilForMalformedPairs() {
        XCTAssertNil(parseWWWAuthenticate("Bearer error"))
        XCTAssertNil(parseWWWAuthenticate("Bearer error=\"invalid_token\", malformed"))
        XCTAssertNil(parseWWWAuthenticate("error=\"invalid_token\""))
    }
}


