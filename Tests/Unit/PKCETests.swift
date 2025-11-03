import SMART
import XCTest

final class PKCETests: XCTestCase {
    func testGenerateProducesVerifierWithinBounds() {
        let pkce = PKCE.generate()

        XCTAssertEqual(pkce.method, "S256")
        XCTAssertEqual(pkce.codeVerifier.count, 64)
        XCTAssertFalse(pkce.codeVerifier.isEmpty)

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        XCTAssertTrue(pkce.codeVerifier.unicodeScalars.allSatisfy { allowedCharacters.contains($0) })
    }

    func testGenerateCodeVerifierRespectsMinimumAndMaximumLength() {
        let shortVerifier = PKCE.generateCodeVerifier(length: 10)
        XCTAssertGreaterThanOrEqual(shortVerifier.count, 43)
        XCTAssertEqual(shortVerifier.count, 43)

        let longVerifier = PKCE.generateCodeVerifier(length: 180)
        XCTAssertLessThanOrEqual(longVerifier.count, 128)
        XCTAssertEqual(longVerifier.count, 128)
    }

    func testDeriveCodeChallengeMatchesKnownVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let challenge = PKCE.deriveCodeChallenge(from: verifier)
        XCTAssertEqual(challenge, expectedChallenge)
    }

    func testCodeChallengeUsesURLSafeAlphabet() {
        let verifier = PKCE.generateCodeVerifier(length: 96)
        let challenge = PKCE.deriveCodeChallenge(from: verifier)

        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }
}

