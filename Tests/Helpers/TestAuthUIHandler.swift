import Foundation
import OAuth2

@testable import SMART

struct TestAuthUIHandler: AuthUIHandler {
	@MainActor
	func presentAuthSession(
		startURL: URL,
		callbackScheme: String,
		oauth: OAuth2
	) async throws -> URL {
		throw SMARTError.generic("UI handler not expected in tests.")
	}

	@MainActor
	func cancelOngoingAuthSession() {}

	@MainActor
	func presentPatientSelector(
		server: Server,
		parameters: OAuth2JSON,
		oauth: OAuth2
	) async throws -> OAuth2JSON {
		throw SMARTError.generic("Patient selection not expected in tests.")
	}
}
