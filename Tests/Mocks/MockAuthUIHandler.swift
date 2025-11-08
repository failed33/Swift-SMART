import OAuth2
import XCTest

@testable import SMART

@MainActor
final class MockAuthUIHandler: AuthUIHandler {
	enum InvocationError: Error, Equatable {
		case unexpectedAuthSession
		case unexpectedPatientSelector
	}

	var authSessionResult: Result<URL, Error>?
	var patientSelectorResult: Result<OAuth2JSON, Error>?

	private(set) var presentedAuthURL: URL?
	private(set) var presentedCallbackScheme: String?
	private(set) var cancelCallCount = 0

	func presentAuthSession(
		startURL: URL,
		callbackScheme: String,
		oauth: OAuth2
	) async throws -> URL {
		presentedAuthURL = startURL
		presentedCallbackScheme = callbackScheme

		guard let authSessionResult else {
			throw InvocationError.unexpectedAuthSession
		}
		cancelCallCount = 0
		return try authSessionResult.get()
	}

	func cancelOngoingAuthSession() {
		cancelCallCount += 1
	}

	func presentPatientSelector(
		server: Server,
		parameters: OAuth2JSON,
		oauth: OAuth2
	) async throws -> OAuth2JSON {
		guard let patientSelectorResult else {
			throw InvocationError.unexpectedPatientSelector
		}
		return try patientSelectorResult.get()
	}
}
