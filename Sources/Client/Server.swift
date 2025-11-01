//
//  Server.swift
//  Swift-SMART
//
//  Rewritten for FHIR R5 + HTTPClient/FHIRClient architecture.
//

import Combine
import CombineSchedulers
import FHIRClient
import Foundation
import HTTPClient
import HTTPClientLive
import ModelsR5
import OAuth2

open class Server {
	public let baseURL: URL
	public let aud: String

	public private(set) var name: String?

	var auth: Auth? {
		didSet {
			oauthInterceptor.auth = auth

			if let oauth: OAuth2 = auth?.oauth {
				oauth.onBeforeDynamicClientRegistration = onBeforeDynamicClientRegistration
				if let logger = logger {
					oauth.logger = logger
				}
			}

			if let auth {
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
		auth?.oauth?.idToken
	}

	public var refreshToken: String? {
		auth?.oauth?.refreshToken
	}

	open var onBeforeDynamicClientRegistration: ((URL) -> OAuth2DynReg)? {
		didSet {
			if let oauth = auth?.oauth {
				oauth.onBeforeDynamicClientRegistration = onBeforeDynamicClientRegistration
			}
		}
	}

	open var logger: OAuth2Logger? {
		didSet {
			auth?.oauth?.logger = logger
		}
	}

	public private(set) var fhirClient: FHIRClient

	public private(set) var launchContext: LaunchContext?

	public var mustAbortAuthorization = false

	private let receiveQueue: AnySchedulerOf<DispatchQueue>
	private let oauthInterceptor: OAuth2BearerInterceptor
	private let httpClient: HTTPClient
	private let configurationDecoder: JSONDecoder = {
		JSONDecoder()
	}()

	private let configurationQueue = DispatchQueue(label: "SMART.Server.Configuration")
	private var cachedSMARTConfiguration: SMARTConfiguration?
	private var configurationTask: _Concurrency.Task<SMARTConfiguration, Error>?
	private var cancellables = Set<AnyCancellable>()

	public init(
		baseURL: URL,
		auth: OAuth2JSON? = nil,
		httpClient: HTTPClient? = nil,
		receiveQueue: AnySchedulerOf<DispatchQueue> = .main
	) {
		baseURL.assertAbsolute()

		self.baseURL = baseURL
		self.aud = baseURL.absoluteString
		self.authSettings = auth
		self.receiveQueue = receiveQueue

		self.oauthInterceptor = OAuth2BearerInterceptor(auth: nil)

		if let httpClient {
			self.httpClient = httpClient
		} else {
			let configuration = URLSessionConfiguration.default
			self.httpClient = DefaultHTTPClient(
				urlSessionConfiguration: configuration,
				interceptors: [oauthInterceptor]
			)
		}

		self.fhirClient = FHIRClient(
			server: baseURL,
			httpClient: self.httpClient,
			receiveQueue: receiveQueue
		)

		didSetAuthSettings()
	}

	// MARK: - Discovery

	open func getSMARTConfiguration(
		forceRefresh: Bool = false,
		completion: @escaping (Result<SMARTConfiguration, Error>) -> Void
	) {
		let task = startSMARTConfigurationTask(forceRefresh: forceRefresh)

		_Concurrency.Task {
			do {
				let configuration = try await task.value
				completion(.success(configuration))
			} catch {
				completion(.failure(error))
			}
		}
	}

	private func startSMARTConfigurationTask(forceRefresh: Bool)
		-> _Concurrency.Task<SMARTConfiguration, Error>
	{
		configurationQueue.sync {
			if !forceRefresh, let cachedSMARTConfiguration {
				return _Concurrency.Task(priority: nil) { cachedSMARTConfiguration }
			}

			if !forceRefresh, let configurationTask {
				return configurationTask
			}

			let task = _Concurrency.Task<SMARTConfiguration, Error> {
				let wellKnownURL = SMARTConfiguration.wellKnownURL(for: self.baseURL)
				var request = URLRequest(url: wellKnownURL)
				request.httpMethod = "GET"

				let response = try await self.httpClient.sendAsync(
					request: request, interceptors: [])

				guard (200..<300).contains(response.status.rawValue) else {
					throw SMARTConfigurationError.invalidHTTPStatus(response.status.rawValue)
				}

				let configuration = try self.configurationDecoder.decode(
					SMARTConfiguration.self, from: response.data)

				self.configurationQueue.sync {
					self.cachedSMARTConfiguration = configuration
					self.configurationTask = nil
				}

				return configuration
			}

			configurationTask = task
			return task
		}
	}

	// MARK: - Readiness

	open func ready(callback: @escaping (Error?) -> Void) {
		if auth != nil {
			callback(nil)
			return
		}

		getSMARTConfiguration { [weak self] result in
			guard let self else {
				callback(SMARTError.configuration("Server deallocated"))
				return
			}

			switch result {
			case .success(let configuration):
				self.mergeAuthSettings(with: configuration)

				if self.auth != nil || self.instantiateAuthFromAuthSettings() {
					callback(nil)
				} else {
					callback(
						SMARTError.configuration(
							"Failed to detect the authorization method from SMART configuration"))
				}

			case .failure(let error):
				callback(error)
			}
		}
	}

	private func mergeAuthSettings(with configuration: SMARTConfiguration) {
		var settings = authSettings ?? OAuth2JSON()

		if settings["authorize_uri"] == nil {
			settings["authorize_uri"] = configuration.authorizationEndpoint.absoluteString
		}
		if settings["token_uri"] == nil {
			settings["token_uri"] = configuration.tokenEndpoint.absoluteString
		}
		if settings["registration_uri"] == nil,
			let registration = configuration.registrationEndpoint
		{
			settings["registration_uri"] = registration.absoluteString
		}
		if settings["aud"] == nil {
			settings["aud"] = aud
		}

		authSettings = settings
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

		auth = Auth(type: type, server: self, settings: authSettings)
		return true
	}

	// MARK: - Authorization Flow

	open func authorize(
		with properties: SMARTAuthProperties,
		callback: @escaping (_ patient: Patient?, _ error: Error?) -> Void
	) {
		ready { error in
			if self.mustAbortAuthorization {
				self.mustAbortAuthorization = false
				callback(nil, nil)
				return
			}

			if let error {
				callback(nil, error)
				return
			}

			guard let auth = self.auth else {
				callback(nil, SMARTError.missingAuthorization)
				return
			}

			auth.authorize(with: properties) { parameters, error in
				if self.mustAbortAuthorization {
					self.mustAbortAuthorization = false
					callback(nil, nil)
					return
				}

				if let error {
					callback(nil, error)
					return
				}

				if let patient = parameters?["patient_resource"] as? ModelsR5.Patient {
					callback(patient, nil)
					return
				}

				if let patientId = parameters?["patient"] as? String {
					self.fetchPatient(id: patientId) { result in
						self.logger?.debug("SMART", msg: "Did read patient with result \(result)")
						switch result {
						case .success(let patient):
							callback(patient, nil)
						case .failure(let error):
							callback(nil, error)
						}
					}
					return
				}

				callback(nil, nil)
			}
		}
	}

	open func abort() {
		mustAbortAuthorization = true
		auth?.abort()
	}

	func reset() {
		abort()
		auth?.reset()
	}

	open var authClientCredentials: (id: String, secret: String?, name: String?)? {
		guard let oauth = auth?.oauth, let clientId = oauth.clientId, !clientId.isEmpty else {
			return nil
		}
		return (clientId, oauth.clientSecret, oauth.clientName)
	}

	open func registerIfNeeded(callback: @escaping (_ json: OAuth2JSON?, _ error: Error?) -> Void) {
		ready { error in
			if let error {
				callback(nil, error)
				return
			}

			guard let oauth = self.auth?.oauth else {
				callback(nil, SMARTError.missingAuthorization)
				return
			}

			oauth.registerClientIfNeeded(callback: callback)
		}
	}

	func forgetClientRegistration() {
		auth?.forgetClientRegistration()
		auth = nil
	}

	func updateLaunchContext(_ context: LaunchContext?) {
		launchContext = context
	}

	func fetchPatient(id: String, completion: @escaping (Result<ModelsR5.Patient, Error>) -> Void) {
		let operation = DecodingFHIRRequestOperation<ModelsR5.Patient>(
			path: "Patient/\(id)",
			headers: ["Accept": "application/fhir+json"]
		)

		var cancellable: AnyCancellable?
		cancellable = fhirClient.execute(operation: operation)
			.sink(
				receiveCompletion: { [weak self] result in
					if let cancellable {
						self?.cancellables.remove(cancellable)
					}
					if case .failure(let error) = result {
						completion(.failure(error))
					}
				},
				receiveValue: { patient in
					completion(.success(patient))
				})

		if let cancellable {
			cancellables.insert(cancellable)
		}
	}
}

extension URL {
	fileprivate func assertAbsolute() {
		precondition(scheme != nil, "Server baseURL must be absolute")
	}
}

public typealias FHIRBaseServer = Server
