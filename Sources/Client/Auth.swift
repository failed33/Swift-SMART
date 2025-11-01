//
//  Auth.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/11/14.
//  Copyright (c) 2014 SMART Health IT. All rights reserved.
//

import Foundation

/// The OAuth2-type to use.
enum AuthType: String {
	case none = "none"
	case implicitGrant = "implicit"
	case codeGrant = "authorization_code"
	case clientCredentials = "client_credentials"
}

/// Describes the OAuth2 authentication method to be used.
class Auth {

	/// The authentication type to use.
	let type: AuthType

	/**
	Settings to be used to initialize the OAuth2 subclass. Supported keys:
	
	- client_id
	- registration_uri
	- authorize_uri
	- token_uri
	- title
	*/
	var settings: OAuth2JSON?

	/// The server this instance belongs to.
	unowned let server: Server

	/// The authentication object, used internally.
	var oauth: OAuth2? {
		didSet {
			if let logger = server.logger {
				oauth?.logger = logger
			} else if let logger = oauth?.logger {
				server.logger = logger
			}
		}
	}

	/// The configuration for the authorization in progress.
	var authProperties: SMARTAuthProperties?

	/// Context used during authorization to pass OS-specific information, handled in the extensions.
	var authContext: AnyObject?

	/// The closure to call when authorization finishes.
	var authCallback: ((_ parameters: OAuth2JSON?, _ error: Error?) -> Void)?

	/// Parsed SMART launch context returned from the token response.
	var launchContext: LaunchContext?

	/// Launch parameter supplied by the EHR launch sequence.
	var launchParameter: String?

	/**
	Designated initializer.
	
	- parameter type: The authorization type to use
	- parameter server: The server these auth settings apply to
	- parameter settings: Authentication settings
	*/
	init(type: AuthType, server: Server, settings: OAuth2JSON?) {
		self.type = type
		self.server = server
		self.settings = settings
		if let sett = self.settings {
			self.configure(withSettings: sett)
		}
	}

	/**
	Convenience initializer from the server cabability statement's rest.security parts.
	
	- parameter fromCapabilitySecurity: The server cabability statement's rest.security pieces to inspect
	- parameter server:                 The server to use
	- parameter settings:               Settings, mostly passed on to the OAuth2 instance
	*/
	convenience init?(
		fromCapabilitySecurity security: CapabilityStatementRestSecurity, server: Server,
		settings: OAuth2JSON?
	) {
		var authSettings = settings ?? OAuth2JSON(minimumCapacity: 3)

		if let services = security.service {
			for service in services {
				server.logger?.debug(
					"SMART", msg: "Server supports REST security via “\(service.text ?? "unknown")”"
				)
				if let codings = service.coding {
					for coding in codings {
						if "OAuth2" == coding.code || "SMART-on-FHIR" == coding.code {
							// TODO: what is this good for anyway?
						}
					}
				}
			}
		}

		// SMART OAuth2 endpoints are exposed via extensions on the security block
		if let smartAuthExtensions = security.extensions(
			for: "http://fhir-registry.smarthealthit.org/StructureDefinition/oauth-uris"
		).first?.`extension` {
			for subExtension in smartAuthExtensions {
				guard let url = subExtension.url.value?.url else { continue }
				let valueString: String?
				switch subExtension.value {
				case .uri(let primitive):
					valueString = primitive.value?.url.absoluteString
				case .url(let primitive):
					valueString = primitive.value?.url.absoluteString
				default:
					valueString = nil
				}
				guard let endpoint = valueString else { continue }
				switch url.lastPathComponent {
				case "authorize":
					authSettings["authorize_uri"] = endpoint
				case "token":
					authSettings["token_uri"] = endpoint
				case "register":
					authSettings["registration_uri"] = endpoint
				default:
					break
				}
			}
		}

		let hasAuthURI = (nil != authSettings["authorize_uri"])
		if !hasAuthURI {
			server.logger?.warn(
				"SMART",
				msg: "Unsupported security services, will proceed without authorization method")
			return nil
		}
		let hasTokenURI = (nil != authSettings["token_uri"])
		self.init(
			type: (hasTokenURI ? .codeGrant : .implicitGrant), server: server,
			settings: authSettings)
	}

	// MARK: - Configuration

	/**
	Finalize instance setup based on type and the a settings dictionary.
	
	- parameter withSettings: A dictionary with auth settings, passed on to OAuth2*()
	*/
	func configure(withSettings settings: OAuth2JSON) {
		var preparedSettings = settings
		if type == .codeGrant && preparedSettings["use_pkce"] == nil {
			preparedSettings["use_pkce"] = true
		}
		switch type {
		case .codeGrant:
			oauth = OAuth2CodeGrant(settings: preparedSettings)
		case .implicitGrant:
			oauth = OAuth2ImplicitGrant(settings: preparedSettings)
		case .clientCredentials:
			oauth = OAuth2ClientCredentials(settings: preparedSettings)
		default:
			oauth = nil
		}
		if type == .codeGrant {
			oauth?.clientConfig.useProofKeyForCodeExchange = true
		}
	}

	/**
	Reset auth, which includes setting authContext to nil and purging any known access and refresh tokens.
	*/
	func reset() {
		authContext = nil
		oauth?.forgetTokens()
	}

	// MARK: - OAuth

	/**
	Starts the authorization flow, either by opening an embedded web view or switching to the browser.
	
	Automatically adds the correct "launch*" scope, according to the authorization property granularity.
	
	If you use the OS browser to authorize, remember that you need to intercept the callback from the browser and call the client's
	`didRedirect()` method, which redirects to this instance's `handleRedirect()` method.
	
	If selecting a patient is part of the authorization flow, will add a "patient" key with the patient-id to the returned dictionary. On
	native patient selection adds a "patient_resource" key with the patient resource.
	
	- parameter properties: The authorization properties to use
	- parameter callback:   The callback to call when authorization finishes (or is aborted)
	*/
	func authorize(
		with properties: SMARTAuthProperties,
		callback: @escaping ((_ parameters: OAuth2JSON?, _ error: Error?) -> Void)
	) {
		if nil != authCallback {
			abort()
		}

		authProperties = properties
		authCallback = callback

		// authorization via OAuth2
		if let oa = oauth {
			if oa.hasUnexpiredAccessToken() {
				if properties.granularity != .patientSelectWeb {
					server.logger?.debug(
						"SMART",
						msg:
							"Have an unexpired access token and don't need web patient selection: not requesting a new token"
					)
					authDidSucceed(withParameters: OAuth2JSON(minimumCapacity: 0))
					return
				}
				server.logger?.debug(
					"SMART",
					msg:
						"Have an unexpired access token but want web patient selection: starting auth flow"
				)
				oa.forgetTokens()
			}

			// adjust the scope for desired auth properties
			let scope = updatedScope(from: oa.scope, properties: properties)
			oa.scope = scope

			// start authorization (method implemented in iOS and OS X extensions)
			callOnMainThread { [weak self] in
				guard let self else { return }
				self.authorize(with: oa, properties: properties) { parameters, error in
					if let error = error {
						self.authDidFail(withError: error)
					} else {
						self.authDidSucceed(withParameters: parameters ?? OAuth2JSON())
					}
				}
			}
		}

		// open server?
		else if .none == type {
			authDidSucceed(withParameters: OAuth2JSON(minimumCapacity: 0))
		} else {
			authDidFail(withError: SMARTError.generic("I am not yet set up to authorize"))
		}
	}

	func handleRedirect(_ redirect: URL) -> Bool {
		guard let oauth = oauth, oauth.isAuthorizing else {
			return false
		}
		do {
			try oauth.handleRedirectURL(redirect)
			return true
		} catch {}
		return false
	}

	internal func authDidSucceed(withParameters parameters: OAuth2JSON) {
		var enrichedParameters = parameters
		let context = parseLaunchContext(from: parameters)
		launchContext = context
		server.updateLaunchContext(context)
		if let context,
			let data = try? JSONEncoder().encode(context),
			let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
		{
			enrichedParameters["launch_context"] = json
		}
		if let props = authProperties, props.granularity == .patientSelectNative {
			server.logger?.debug(
				"SMART",
				msg:
					"Showing native patient selector after authorizing with parameters \(enrichedParameters)"
			)
			callOnMainThread { [weak self] in
				self?.showPatientList(withParameters: enrichedParameters)
			}
		} else {
			server.logger?.debug(
				"SMART", msg: "Did authorize with parameters \(enrichedParameters)")
			processAuthCallback(parameters: enrichedParameters, error: nil)
		}

		launchParameter = nil
	}

	internal func authDidFail(withError error: Error?) {
		if let error = error {
			server.logger?.debug("SMART", msg: "Failed to authorize with error: \(error)")
		}
		processAuthCallback(parameters: nil, error: error)
	}

	func abort() {
		server.logger?.debug("SMART", msg: "Aborting authorization")
		processAuthCallback(parameters: nil, error: nil)
	}

	func forgetClientRegistration() {
		oauth?.forgetClient()
	}

	func processAuthCallback(parameters: OAuth2JSON?, error: Error?) {
		if nil != authCallback {
			authCallback!(parameters, error)
			authCallback = nil
		}
	}

	private func updatedScope(from originalScope: String?, properties: SMARTAuthProperties)
		-> String
	{
		var components = Set(
			originalScope?.split(separator: " ").map(String.init).filter { !$0.isEmpty } ?? [])
		if components.isEmpty {
			components = ["user/*.cruds", "openid", "profile"]
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
		normalized.insert("profile")

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

	private func parseLaunchContext(from parameters: OAuth2JSON) -> LaunchContext? {
		let contextKeys: Set<String> = [
			"patient",
			"encounter",
			"fhirContext",
			"need_patient_banner",
			"smart_style_url",
			"intent",
			"tenant",
			"location",
		]
		guard parameters.keys.contains(where: { contextKeys.contains($0) }) else {
			return nil
		}
		do {
			let data = try JSONSerialization.data(withJSONObject: parameters, options: [])
			let decoder = JSONDecoder()
			let context = try decoder.decode(LaunchContext.self, from: data)
			return context
		} catch {
			server.logger?.warn("SMART", msg: "Failed to parse launch context: \(error)")
			return nil
		}
	}

	// MARK: - Requests

	/**
	Returns a signed request, nil if the receiver cannot produce a signed request.
	
	- parameter forURL: The URL to request a resource from
	- returns:          A URL request preconfigured and signed
	*/
	func signedRequest(forURL url: URL) -> URLRequest? {
		return oauth?.request(forURL: url)
	}
}
