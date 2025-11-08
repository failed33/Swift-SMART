import OAuth2
import XCTest
import _Concurrency

@testable import SMART

@MainActor
final class AuthCoreTests: XCTestCase {

	func testConfigureScopeUpdatesOAuth() throws {
		let oauth = MockOAuth2()
		let core = AuthCore(oauth: oauth, launchContext: nil, launchParameter: nil, logger: nil)

		core.configure(scope: "user/*.read")

		XCTAssertEqual(oauth.scope, "user/*.read")
	}

	func testHasUnexpiredTokenReflectsOAuthState() {
		let oauth = MockOAuth2()
		oauth.accessToken = "token"
		oauth.forceTokenExpiration = false

		let core = AuthCore(oauth: oauth, launchContext: nil, launchParameter: nil, logger: nil)

		let hasToken = core.hasUnexpiredToken()
		XCTAssertTrue(hasToken)

		oauth.forceTokenExpiration = true
		let expired = core.hasUnexpiredToken()
		XCTAssertFalse(expired)
	}

	func testLaunchContextParsingAndEncodingRoundTrip() throws {
		let core = AuthCore(oauth: nil, launchContext: nil, launchParameter: nil, logger: nil)
		let parameters: OAuth2JSON = [
			"patient": "123",
			"encounter": "enc-1",
			"need_patient_banner": true,
			"tenant": "tenant-a",
			"custom_key": "custom-value",
		]

		let context = core.parseLaunchContext(from: parameters)
		XCTAssertEqual(context?.patient, "123")
		XCTAssertEqual(context?.encounter, "enc-1")
		XCTAssertEqual(context?.needPatientBanner, true)
		XCTAssertEqual(context?.additionalFields["custom_key"]?.value as? String, "custom-value")

		guard let context else {
			XCTFail("Expected launch context")
			return
		}

		let encoded = core.encodeLaunchContext(context)
		XCTAssertEqual(encoded?["patient"] as? String, "123")
		XCTAssertEqual(encoded?["custom_key"] as? String, "custom-value")
	}

	func testHandleRedirectWithoutOAuthThrows() {
		let core = AuthCore(oauth: nil, launchContext: nil, launchParameter: nil, logger: nil)
		XCTAssertThrowsError(try core.handleRedirect(URL(string: "smart://callback")!)) { error in
			guard case SMARTError.missingAuthorization = error else {
				XCTFail("Expected SMARTError.missingAuthorization")
				return
			}
		}
	}

	func testLaunchParameterStoredAndRetrieved() {
		let core = AuthCore(oauth: nil, launchContext: nil, launchParameter: nil, logger: nil)
		core.updateLaunchParameter("launch-token")

		let stored = core.currentLaunchParameter()
		XCTAssertEqual(stored, "launch-token")
	}
}
