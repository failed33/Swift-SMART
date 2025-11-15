//
//  Auth.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/11/14.
//  Copyright (c) 2014 SMART Health IT. All rights reserved.
//

import Foundation
import OAuth2
import _Concurrency

private struct OAuth2JSONBox: @unchecked Sendable {
	let value: OAuth2JSON
}

/// The OAuth2-type to use.
enum AuthType: String, Sendable {
	case none = "none"
	case implicitGrant = "implicit"
	case codeGrant = "authorization_code"
	case clientCredentials = "client_credentials"
}

/// Describes the OAuth2 authentication method to be used.
@MainActor
final class Auth {

	let type: AuthType
	private(set) var settings: OAuth2JSON?
	unowned let server: Server
	private let aud: String

	private let core: AuthCore
	private let uiHandler: AuthUIHandler
	private var cachedLaunchParameter: String?
	private var authorizationInFlight = false
	private var currentLogger: OAuth2Logger?
	private let allowInsecureConnections: Bool

	init(
		type: AuthType,
		server: Server,
		aud: String,
		initialLogger: OAuth2Logger?,
		settings: OAuth2JSON?,
		uiHandler: AuthUIHandler,
		allowInsecureConnections: Bool = false
	) {
		self.type = type
		self.server = server
		self.aud = aud
		self.settings = settings
		self.uiHandler = uiHandler
		self.currentLogger = initialLogger
		self.allowInsecureConnections = allowInsecureConnections

		let oauth = Auth.makeOAuth(type: type, settings: settings)
		self.core = AuthCore(
			oauth: oauth,
			launchContext: nil,
			launchParameter: nil,
			logger: initialLogger
		)
		cachedLaunchParameter = nil

		if let oauth {
			configureOAuth(oauth)
		}
	}

	func launchParameter() -> String? {
		cachedLaunchParameter
	}

	func setLaunchParameter(_ newValue: String?) {
		cachedLaunchParameter = newValue
		core.updateLaunchParameter(newValue)
	}

	func configure(withSettings settings: OAuth2JSON) {
		self.settings = settings
		let oauth = Auth.makeOAuth(type: type, settings: settings)
		core.updateOAuth(oauth)
		core.updateLogger(currentLogger)
		if let oauth {
			configureOAuth(oauth)
		}
	}

	func updateLogger(_ logger: OAuth2Logger?) {
		currentLogger = logger
		core.updateLogger(logger)
	}

	func updateDynamicClientRegistration(_ handler: (@Sendable (URL) -> OAuth2DynReg?)?) {
		core.setDynamicClientRegistrationHandler(handler)
	}

	func hasUnexpiredToken() -> Bool {
		core.hasUnexpiredToken()
	}

	func currentOAuth() -> OAuth2? {
		core.currentOAuth()
	}

	func authorize(with properties: SMARTAuthProperties) async throws -> OAuth2JSON {
		if core.hasUnexpiredToken(), properties.granularity != .patientSelectWeb {
			return try await postAuth(properties, [:])
		}

		let oauth = try requireOAuth()
		let normalizedScope = updatedScope(from: oauth.scope, properties: properties)
		core.configure(scope: normalizedScope)

		var params: OAuth2StringDict = ["aud": aud]
		if let launch = cachedLaunchParameter, !launch.isEmpty {
			params["launch"] = launch
		}

		let resultParameters: OAuth2JSON
		if properties.embedded {
			resultParameters = try await awaitAuthorizationResult {
				let startURL = try self.core.authorizeURL(params: params)
				guard let redirectTemplate = self.core.redirectScheme() else {
					throw SMARTError.generic("Missing redirect URI")
				}
				let callbackScheme = URL(string: redirectTemplate)?.scheme ?? redirectTemplate
				let redirectURL = try await self.uiHandler.presentAuthSession(
					startURL: startURL,
					callbackScheme: callbackScheme,
					oauth: oauth
				)
				try self.core.handleRedirect(redirectURL)
			}
		} else {
			resultParameters = try await awaitAuthorizationResult {
				let startURL = try self.core.authorizeURL(params: params)
				try self.core.openAuthorizeURLInBrowser(startURL)
			}
		}

		return try await postAuth(properties, resultParameters)
	}

	func reset() {
		core.updateLaunchContext(nil)
		core.updateLaunchParameter(nil)
		core.forgetTokens()
	}

	func handleRedirect(_ redirect: URL) -> Bool {
		guard let template = self.core.redirectScheme() else {
			return false
		}

		guard redirectMatchesTemplate(redirect, template: template) else {
			return false
		}

		do {
			try self.core.handleRedirect(redirect)
			return true
		} catch {
			let oauthError = asOAuth2Error(error)
			core.currentOAuth()?.didFail(with: oauthError)
			return false
		}
	}

	func forgetClientRegistration() {
		core.forgetClient()
	}

	func signedRequest(forURL url: URL) -> URLRequest? {
		core.signedRequest(forURL: url)
	}

	func accessToken() -> String? {
		core.currentAccessToken()
	}

	func refreshAccessToken(params: OAuth2StringDict? = nil) async throws {
		try await core.withOAuth { oauth in
			try await withCheckedThrowingContinuation {
				(continuation: CheckedContinuation<Void, Error>) in
				oauth.tryToObtainAccessTokenIfNeeded(params: params) { _, error in
					if let error {
						continuation.resume(throwing: error)
						return
					}
					if oauth.hasUnexpiredAccessToken() {
						continuation.resume(returning: ())
					} else {
						continuation.resume(throwing: OAuth2Error.noRefreshToken)
					}
				}
			}
		}
	}

	func clientCredentials() -> (id: String, secret: String?, name: String?)? {
		guard let oauth = core.currentOAuth() else { return nil }
		guard let clientId = oauth.clientId, !clientId.isEmpty else { return nil }
		return (clientId, oauth.clientSecret, oauth.clientName)
	}

	func idToken() -> String? {
		core.currentIDToken()
	}

	func refreshTokenValue() -> String? {
		core.currentRefreshToken()
	}

	func registerClientIfNeeded() async throws -> OAuth2JSON? {
		let result: OAuth2JSONBox? = try await core.withOAuth { oauth in
			try await withCheckedThrowingContinuation {
				(continuation: CheckedContinuation<OAuth2JSONBox?, Error>) in
				oauth.registerClientIfNeeded { json, error in
					if let error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume(returning: json.map(OAuth2JSONBox.init))
					}
				}
			}
		}
		return result?.value
	}

	func tokenSnapshot() async -> OAuth2JSON {
		(try? await core.withOAuth { oauth -> OAuth2JSON in
			var snapshot: OAuth2JSON = [:]
			snapshot["access_token"] =
				(oauth.clientConfig.accessToken != nil) ? "<redacted>" : "<missing>"
			if oauth.clientConfig.refreshToken != nil {
				snapshot["refresh_token"] = "<redacted>"
			}
			if let scope = oauth.scope {
				snapshot["scope"] = scope
			}
			if let expiry = oauth.clientConfig.accessTokenExpiry {
				let formatter = ISO8601DateFormatter()
				snapshot["expires_at"] = formatter.string(from: expiry)
			}
			return snapshot
		}) ?? [:]
	}

	func withOAuth<Result>(_ operation: @MainActor @Sendable (OAuth2) async throws -> Result)
		async throws -> Result
	{
		try await core.withOAuth(operation)
	}

	func isAwaitingAuthorization() -> Bool {
		authorizationInFlight
	}

	#if DEBUG
		func replaceOAuthForTesting(_ oauth: OAuth2?) {
			core.updateOAuth(oauth)
			if let oauth {
				configureOAuth(oauth)
			}
		}
	#endif

	func abort() {
		uiHandler.cancelOngoingAuthSession()
		core.terminateAuthorization()
	}

	func updatedScope(from originalScope: String?, properties: SMARTAuthProperties) -> String {
		var components = Set(
			originalScope?.split(separator: " ").map(String.init).filter { !$0.isEmpty } ?? [])
		if components.isEmpty {
			components = ["user/*.cruds", "openid", "fhirUser"]
		}

		var normalized = Set<String>()
		for component in components {
			switch component {
			case "user/*.*":
				normalized.insert("user/*.cruds")
			case "patient/*.*":
				normalized.insert("patient/*.rs")
			case "system/*.*":
				normalized.insert("system/*.cruds")
			case let value where value.hasSuffix(".read"):
				normalized.insert(value.replacingOccurrences(of: ".read", with: ".rs"))
			case let value where value.hasSuffix(".write"):
				normalized.insert(value.replacingOccurrences(of: ".write", with: ".cruds"))
			default:
				normalized.insert(component)
			}
		}

		normalized.insert("openid")
		normalized.insert("fhirUser")

		switch properties.granularity {
		case .tokenOnly:
			break
		case .launchContext:
			normalized.insert("launch")
		case .patientSelectWeb:
			normalized.insert("launch/patient")
		case .patientSelectNative:
			normalized.insert("launch/patient")
		}

		return normalized.sorted().joined(separator: " ")
	}

	// MARK: - Helpers

	private static func makeOAuth(type: AuthType, settings: OAuth2JSON?) -> OAuth2? {
		guard var prepared = settings else {
			return nil
		}

		if type == .codeGrant && prepared["use_pkce"] == nil {
			prepared["use_pkce"] = true
		}

		let oauth: OAuth2?
		switch type {
		case .codeGrant:
			oauth = OAuth2CodeGrant(settings: prepared)
		case .implicitGrant:
			oauth = OAuth2ImplicitGrant(settings: prepared)
		case .clientCredentials:
			oauth = OAuth2ClientCredentials(settings: prepared)
		case .none:
			oauth = nil
		}

		if let oauthCodeGrant = oauth as? OAuth2CodeGrant {
			oauthCodeGrant.clientConfig.useProofKeyForCodeExchange = true
		}

		return oauth
	}

	private func configureOAuth(_ oauth: OAuth2) {
		oauth.logger = currentLogger

		// Configure URLSession to accept self-signed certificates for localhost if enabled
		if allowInsecureConnections {
			let delegate = InsecureConnectionDelegate()
			let configuration = URLSessionConfiguration.default
			configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
			oauth.sessionDelegate = delegate
			oauth.sessionConfiguration = configuration
		}
	}

	private func requireOAuth() throws -> OAuth2 {
		if let oauth = core.currentOAuth() {
			return oauth
		}
		throw SMARTError.missingAuthorization
	}

	private func awaitAuthorizationResult(
		operation: @escaping () async throws -> Void
	) async throws -> OAuth2JSON {
		authorizationInFlight = true
		defer { authorizationInFlight = false }

		let stream = core.waitForAuthorization()

		do {
			try await operation()

			for await outcome in stream {
				switch outcome {
				case .success(let parameters):
					return parameters
				case .failure(let error):
					throw error
				}
			}

			throw OAuth2Error.generic("Authorization stream ended without result")
		} catch {
			uiHandler.cancelOngoingAuthSession()
			core.terminateAuthorization()
			throw error
		}
	}

	private func postAuth(
		_ properties: SMARTAuthProperties,
		_ parameters: OAuth2JSON
	) async throws -> OAuth2JSON {
		var enriched = parameters

		if let context = core.parseLaunchContext(from: parameters) {
			core.updateLaunchContext(context)
			server.updateLaunchContext(context)
			if let encoded = core.encodeLaunchContext(context) {
				enriched["launch_context"] = encoded
			}
		} else {
			core.updateLaunchContext(nil)
			server.updateLaunchContext(nil)
		}

		if properties.granularity == .patientSelectNative {
			let oauth = try requireOAuth()
			enriched = try await uiHandler.presentPatientSelector(
				server: server,
				parameters: enriched,
				oauth: oauth
			)
		} else {
			if let logger = server.logger {
				logger.debug("SMART", msg: "Did authorize with parameters \(enriched)")
			}
		}

		cachedLaunchParameter = nil
		core.updateLaunchParameter(nil)

		return enriched
	}

	private func redirectMatchesTemplate(_ redirect: URL, template: String) -> Bool {
		if redirect.absoluteString.hasPrefix(template) {
			return true
		}
		if let templateURL = URL(string: template) {
			if templateURL.scheme == redirect.scheme && templateURL.host == redirect.host {
				return true
			}
		}
		return false
	}

	private func asOAuth2Error(_ error: Error) -> OAuth2Error {
		if let oauthError = error as? OAuth2Error {
			return oauthError
		}
		return OAuth2Error.generic(error.localizedDescription)
	}
}

/// URLSessionDelegate that accepts self-signed certificates for localhost connections.
/// **FOR DEVELOPMENT USE ONLY** - should never be used in production.
private class InsecureConnectionDelegate: NSObject, URLSessionDelegate {
	func urlSession(
		_ session: URLSession,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		let host = challenge.protectionSpace.host.lowercased()
		let isLoopbackHost = host == "localhost" || host == "127.0.0.1" || host == "::1"
		let isLocalhostAlias = host.hasSuffix(".localhost")

		guard isLoopbackHost || isLocalhostAlias else {
			completionHandler(.performDefaultHandling, nil)
			return
		}

		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
			let serverTrust = challenge.protectionSpace.serverTrust
		{
			let credential = URLCredential(trust: serverTrust)
			completionHandler(.useCredential, credential)
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}
}
