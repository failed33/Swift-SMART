//
//  Server.swift
//  Swift-SMART
//
//  Rewritten for FHIR R5 + HTTPClient/FHIRClient architecture.
//

import CombineSchedulers
import FHIRClient
import Foundation
import HTTPClient
import HTTPClientLive
import ModelsR5
import OAuth2
import _Concurrency

#if canImport(AppKit)
	import AppKit
#endif

@MainActor
public final class Server {
	public let baseURL: URL
	public let aud: String

	private struct SendableBox<Value>: @unchecked Sendable {
		let value: Value

		init(_ value: Value) {
			self.value = value
		}
	}

	public private(set) var name: String?

	private static func makeDefaultAuthUIHandler() -> AuthUIHandler {
		#if os(iOS)
			return iOSAuthUIHandler()
		#elseif os(macOS)
			// TODO: Implement macOSAuthUIHandler
			// return macOSAuthUIHandler(anchorProvider: {
			// 	@MainActor in NSFontPanel.shared.sheetParent
			// })
			return NoUIAuthHandler()
		#else
			return NoUIAuthHandler()
		#endif
	}

	var auth: Auth? {
		didSet {
			oauthInterceptor.auth = auth
			authRefreshInterceptor?.auth = auth

			if let auth {
				let handler = onBeforeDynamicClientRegistration
				let currentLogger = logger
				auth.updateDynamicClientRegistration(handler)
				auth.updateLogger(currentLogger)
				logger?.debug(
					"SMART", msg: "Initialized server auth of type “\(auth.type.rawValue)”")
			}
		}
	}

	var authSettings: OAuth2JSON? {
		didSet {
			didSetAuthSettings()
		}
	}

	public var idToken: String? {
		guard let auth else { return nil }
		return auth.idToken()
	}

	public var refreshToken: String? {
		guard let auth else { return nil }
		return auth.refreshTokenValue()
	}

	public var onBeforeDynamicClientRegistration: (@Sendable (URL) -> OAuth2DynReg)? {
		didSet {
			guard let auth else { return }
			let handler = onBeforeDynamicClientRegistration
			auth.updateDynamicClientRegistration(handler)
		}
	}

	public var logger: OAuth2Logger? {
		didSet {
			guard let auth else { return }
			let currentLogger = logger
			auth.updateLogger(currentLogger)
		}
	}

	public private(set) var fhirClient: FHIRClient

	public private(set) var launchContext: LaunchContext?

	public var mustAbortAuthorization = false

	private let receiveQueue: AnySchedulerOf<DispatchQueue>
	private let oauthInterceptor: OAuth2BearerInterceptor
	private let authRefreshInterceptor: AuthRefreshInterceptor?
	private let retryInterceptor: RetryInterceptor?
	private let retryPolicy: RetryPolicy
	private let httpClient: HTTPClient
	private let allowInsecureConnections: Bool
	private let configurationDecoder: JSONDecoder = {
		JSONDecoder()
	}()
	private let configurationCache = ConfigurationCache()

	public init(
		baseURL: URL,
		auth: OAuth2JSON? = nil,
		httpClient: HTTPClient? = nil,
		receiveQueue: AnySchedulerOf<DispatchQueue> = .main,
		retryPolicy: RetryPolicy? = nil,
		additionalInterceptors: [Interceptor] = [],
		allowInsecureConnections: Bool = false
	) {
		baseURL.assertAbsolute()

		let normalizedBase = baseURL.smartEnsuringTrailingSlash()
		self.baseURL = normalizedBase
		self.aud = baseURL.smartRemovingTrailingSlash()
		self.authSettings = auth
		self.receiveQueue = receiveQueue
		self.allowInsecureConnections = allowInsecureConnections

		self.retryPolicy = retryPolicy ?? RetryPolicy()
		self.oauthInterceptor = OAuth2BearerInterceptor(auth: nil)

		if let httpClient {
			self.authRefreshInterceptor = nil
			self.retryInterceptor = nil
			self.httpClient = httpClient
		} else {
			let configuration = URLSessionConfiguration.default
			let authRefresh = AuthRefreshInterceptor(auth: nil)
			let retry = RetryInterceptor(policy: self.retryPolicy)
			self.authRefreshInterceptor = authRefresh
			self.retryInterceptor = retry
			var composedInterceptors: [Interceptor] = [oauthInterceptor, authRefresh, retry]
			composedInterceptors.append(contentsOf: additionalInterceptors)
			self.httpClient = DefaultHTTPClient(
				urlSessionConfiguration: configuration,
				interceptors: composedInterceptors,
				allowInsecureConnections: allowInsecureConnections
			)
		}

		self.fhirClient = FHIRClient(
			server: normalizedBase,
			httpClient: self.httpClient,
			receiveQueue: receiveQueue
		)

		didSetAuthSettings()
	}

	// MARK: - Discovery

	public func getSMARTConfiguration(forceRefresh: Bool = false) async throws -> SMARTConfiguration
	{
		let task = await startSMARTConfigurationTask(forceRefresh: forceRefresh)
		return try await task.value
	}

	func setMustAbortAuthorization(_ value: Bool) {
		mustAbortAuthorization = value
	}

	func setLogger(_ newLogger: OAuth2Logger?) {
		logger = newLogger
	}

	private func startSMARTConfigurationTask(forceRefresh: Bool) async
		-> _Concurrency.Task<SMARTConfiguration, Error>
	{
		if !forceRefresh, let cached = await configurationCache.cachedConfigurationValue() {
			return _Concurrency.Task(priority: nil) { cached }
		}

		if !forceRefresh, let current = await configurationCache.currentTaskValue() {
			return current
		}

		let task = _Concurrency.Task<SMARTConfiguration, Error> {
			try await self.fetchSMARTConfiguration()
		}

		await configurationCache.store(task: task)
		return task
	}

	private func fetchSMARTConfiguration() async throws -> SMARTConfiguration {
		let wellKnownURL = SMARTConfiguration.wellKnownURL(for: baseURL)
		var request = URLRequest(url: wellKnownURL)
		request.httpMethod = "GET"

		do {
			let client = SendableBox(httpClient)
			let response = try await client.value.sendAsync(
				request: request,
				interceptors: []
			)

			guard (200..<300).contains(response.status.rawValue) else {
				throw SMARTClientError.configuration(
					url: wellKnownURL,
					underlying: SMARTConfigurationError.invalidHTTPStatus(response.status.rawValue)
				)
			}

			let rawConfiguration = try configurationDecoder.decode(
				SMARTConfiguration.self,
				from: response.data
			)
			let configuration = rewriteSMARTConfigurationIfNeeded(rawConfiguration)
			await configurationCache.store(configuration: configuration)
			return configuration
		} catch let error as SMARTClientError {
			await configurationCache.clearTask()
			throw error
		} catch {
			await configurationCache.clearTask()
			throw SMARTClientError.configuration(url: wellKnownURL, underlying: error)
		}
	}

	private func rewriteSMARTConfigurationIfNeeded(_ configuration: SMARTConfiguration)
		-> SMARTConfiguration
	{
		let rewrittenAuthorize = rewriteOAuthEndpointIfNeeded(configuration.authorizationEndpoint)
		let rewrittenToken = rewriteOAuthEndpointIfNeeded(configuration.tokenEndpoint)
		let rewrittenRegistration = configuration.registrationEndpoint.map {
			rewriteOAuthEndpointIfNeeded($0)
		}

		if rewrittenAuthorize == configuration.authorizationEndpoint,
			rewrittenToken == configuration.tokenEndpoint,
			rewrittenRegistration == configuration.registrationEndpoint
		{
			return configuration
		}

		return SMARTConfiguration(
			authorizationEndpoint: rewrittenAuthorize,
			tokenEndpoint: rewrittenToken,
			registrationEndpoint: rewrittenRegistration,
			managementEndpoint: configuration.managementEndpoint,
			introspectionEndpoint: configuration.introspectionEndpoint,
			revocationEndpoint: configuration.revocationEndpoint,
			jwksEndpoint: configuration.jwksEndpoint,
			issuer: configuration.issuer,
			grantTypesSupported: configuration.grantTypesSupported,
			responseTypesSupported: configuration.responseTypesSupported,
			scopesSupported: configuration.scopesSupported,
			codeChallengeMethodsSupported: configuration.codeChallengeMethodsSupported,
			tokenEndpointAuthMethodsSupported: configuration.tokenEndpointAuthMethodsSupported,
			tokenEndpointAuthSigningAlgValuesSupported: configuration
				.tokenEndpointAuthSigningAlgValuesSupported,
			capabilities: configuration.capabilities,
			smartVersion: configuration.smartVersion,
			fhirVersion: configuration.fhirVersion,
			additionalFields: configuration.additionalFields
		)
	}

	// MARK: - Readiness

	public func ready() async throws {
		let configuration = try await getSMARTConfiguration()
		try ensurePKCES256Support(in: configuration)
		mergeAuthSettings(with: configuration)

		if auth == nil, !instantiateAuthFromAuthSettings() {
			throw SMARTError.configuration(
				"Failed to detect the authorization method from SMART configuration")
		}
	}

	private func ensurePKCES256Support(in configuration: SMARTConfiguration) throws {
		guard let methods = configuration.codeChallengeMethodsSupported,
			methods.contains(where: { $0.caseInsensitiveCompare("S256") == .orderedSame })
		else {
			throw SMARTError.configuration(
				"SMART configuration at \(baseURL.absoluteString) does not advertise PKCE S256 support"
			)
		}
	}

	private func mergeAuthSettings(with configuration: SMARTConfiguration) {
		var settings = authSettings ?? OAuth2JSON()

		if settings["authorize_uri"] == nil {
			let endpoint = rewriteOAuthEndpointIfNeeded(configuration.authorizationEndpoint)
			settings["authorize_uri"] = endpoint.absoluteString
		}
		if settings["token_uri"] == nil {
			let endpoint = rewriteOAuthEndpointIfNeeded(configuration.tokenEndpoint)
			settings["token_uri"] = endpoint.absoluteString
		}
		if settings["registration_uri"] == nil,
			let registration = configuration.registrationEndpoint
		{
			let endpoint = rewriteOAuthEndpointIfNeeded(registration)
			settings["registration_uri"] = endpoint.absoluteString
		}
		if settings["aud"] == nil {
			settings["aud"] = aud
		}

		authSettings = settings
	}

	func mergeAuthSettings(_ additional: OAuth2JSON) {
		if authSettings == nil {
			authSettings = additional
		} else {
			for (key, value) in additional {
				authSettings?[key] = value
			}
		}
	}

	/// When running tests against servers that advertise HTTP OAuth endpoints, allow remapping
	/// those endpoints to an HTTPS proxy base via the `SMART_HTTPS_AUTH_BASE` environment variable.
	/// This enables local TLS termination without changing the underlying FHIR base URL.
	private func rewriteOAuthEndpointIfNeeded(_ url: URL) -> URL {
		guard url.scheme?.lowercased() == "http",
			let baseString = ProcessInfo.processInfo.environment["SMART_HTTPS_AUTH_BASE"],
			let base = URL(string: baseString),
			var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
			let baseComponents = URLComponents(url: base, resolvingAgainstBaseURL: false)
		else {
			return url
		}

		self.logger?.debug(
			"SMART",
			msg: "Rewriting OAuth endpoint from \(url.absoluteString) to \(base.absoluteString)")

		urlComponents.scheme = baseComponents.scheme
		urlComponents.host = baseComponents.host
		urlComponents.port = baseComponents.port

		let basePath = (baseComponents.path as NSString).standardizingPath
		let urlPath = (urlComponents.path as NSString).standardizingPath
		let combinedPath: String
		if basePath.isEmpty || basePath == "/" {
			combinedPath = urlPath
		} else {
			let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
			combinedPath = trimmedBase + (urlPath.hasPrefix("/") ? urlPath : "/" + urlPath)
		}
		urlComponents.path = combinedPath

		return urlComponents.url ?? url
	}

	private func didSetAuthSettings() {
		_ = instantiateAuthFromAuthSettings()
	}

	@discardableResult
	func instantiateAuthFromAuthSettings() -> Bool {
		guard let authSettings else { return false }

		var authType: AuthType? = nil

		if let typeString = authSettings["authorize_type"] as? String {
			authType = AuthType(rawValue: typeString)
		}

		if authType == nil || authType == AuthType.none {
			if authSettings["authorize_uri"] != nil {
				authType = authSettings["token_uri"] != nil ? .codeGrant : .implicitGrant
			}
		}

		guard let type = authType else {
			return false
		}

		auth = Auth(
			type: type,
			server: self,
			aud: aud,
			initialLogger: logger,
			settings: authSettings,
			uiHandler: Server.makeDefaultAuthUIHandler(),
			allowInsecureConnections: allowInsecureConnections
		)
		return true
	}

	// MARK: - Authorization Flow

	public func authorize(with properties: SMARTAuthProperties) async throws -> Patient? {
		try await ready()

		guard let auth else {
			throw SMARTError.missingAuthorization
		}

		return try await withTaskCancellationHandler {
			let parameters = try await auth.authorize(with: properties)

			if mustAbortAuthorization {
				mustAbortAuthorization = false
				return nil
			}

			if let patient = parameters["patient_resource"] as? Patient {
				return patient
			}

			if let patientId = parameters["patient"] as? String {
				do {
					let patient = try await readPatient(id: patientId)
					logger?.debug(
						"SMART",
						msg: "Did read patient with result success(\(patientId))")
					return patient
				} catch {
					logger?.debug(
						"SMART",
						msg: "Did read patient with result failure(\(error))")
					throw error
				}
			}

			return nil
		} onCancel: {
			_Concurrency.Task { @MainActor in
				self.mustAbortAuthorization = true
				self.auth?.abort()
			}
		}
	}

	public func abort() {
		mustAbortAuthorization = true
		if let auth {
			auth.abort()
		}
	}

	func reset() {
		mustAbortAuthorization = true
		if let auth {
			auth.abort()
			auth.reset()
		}
	}

	public var authClientCredentials: (id: String, secret: String?, name: String?)? {
		guard let auth else { return nil }
		return auth.clientCredentials()
	}

	public func registerIfNeeded() async throws -> OAuth2JSON? {
		try await ready()
		guard let auth else {
			throw SMARTError.missingAuthorization
		}

		return try await auth.registerClientIfNeeded()
	}

	func forgetClientRegistration() {
		if let auth {
			auth.forgetClientRegistration()
		}
		auth = nil
	}

	func updateLaunchContext(_ context: LaunchContext?) {
		launchContext = context
	}

	func execute<T: FHIRClientOperation>(_ operation: T) async throws -> T.Value where T: Sendable {
		try await fhirClient.execute(operation: operation)
	}

	func scheduleOnReceiveQueue(_ action: @escaping () -> Void) {
		receiveQueue.schedule(action)
	}

	public func read<T: ModelsR5.Resource>(_ type: T.Type, id: String) async throws -> T {
		let resourceName =
			String(describing: type).split(separator: ".").last.map(String.init)
			?? String(describing: type)
		let path = "\(resourceName)/\(id)"
		let operation = DecodingFHIRRequestOperation<T>(
			path: path,
			headers: ["Accept": "application/fhir+json"]
		)

		do {
			let client = SendableBox(fhirClient)
			return try await client.value.execute(operation: operation)
		} catch {
			if let cancellation = error.cancellationError {
				throw cancellation
			}
			let url = URL(string: path, relativeTo: baseURL)
			throw SMARTErrorMapper.mapPublic(error: error, url: url)
		}
	}

	public func readPatient(id: String) async throws -> ModelsR5.Patient {
		try await read(ModelsR5.Patient.self, id: id)
	}

}

#if !os(iOS)
	private struct NoUIAuthHandler: AuthUIHandler {
		@MainActor
		func presentAuthSession(
			startURL: URL,
			callbackScheme: String,
			oauth: OAuth2
		) async throws -> URL {
			throw SMARTError.generic("Authentication UI is not available on this platform.")
		}

		@MainActor
		func cancelOngoingAuthSession() {}

		@MainActor
		func presentPatientSelector(
			server: Server,
			parameters: OAuth2JSON,
			oauth: OAuth2
		) async throws -> OAuth2JSON {
			throw SMARTError.generic("Patient selection UI is not available on this platform.")
		}
	}
#endif

private actor ConfigurationCache {
	private var cachedConfiguration: SMARTConfiguration?
	private var runningTask: _Concurrency.Task<SMARTConfiguration, Error>?

	func cachedConfigurationValue() -> SMARTConfiguration? {
		cachedConfiguration
	}

	func currentTaskValue() -> _Concurrency.Task<SMARTConfiguration, Error>? {
		runningTask
	}

	func store(task: _Concurrency.Task<SMARTConfiguration, Error>) {
		runningTask = task
	}

	func store(configuration: SMARTConfiguration) {
		cachedConfiguration = configuration
		runningTask = nil
	}

	func clearTask() {
		runningTask = nil
	}
}

// MARK: - URL Normalization Helpers

extension URL {
	/// Returns a URL guaranteed to end with a trailing slash so Foundation treats it as a directory
	/// base when resolving relative paths.
	fileprivate func smartEnsuringTrailingSlash() -> URL {
		guard !absoluteString.hasSuffix("/") else { return self }
		// appending an empty path component marked as a directory preserves existing query/fragment.
		return appendingPathComponent("", isDirectory: true)
	}

	/// Returns the absolute string without an optional trailing slash, keeping other components
	/// (scheme, host, query, fragment) untouched.
	fileprivate func smartRemovingTrailingSlash() -> String {
		var absolute = absoluteString
		if absolute.count > 1, absolute.hasSuffix("/") {
			absolute.removeLast()
		}
		return absolute
	}
}

extension URL {
	fileprivate func assertAbsolute() {
		precondition(scheme != nil, "Server baseURL must be absolute")
	}
}

public typealias FHIRBaseServer = Server
