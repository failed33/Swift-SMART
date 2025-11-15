//
//  Client.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/11/14.
//  Copyright (c) 2014 SMART Health IT. All rights reserved.
//

import FHIRClient
import Foundation
import ModelsR5
import OAuth2

/// Describes properties for the authorization flow.
public struct SMARTAuthProperties: Sendable {

	/// Whether the client should use embedded view controllers for the auth flow or just redirect to the OS's browser.
	public var embedded = true

	/// How granular the authorize flow should be.
	public var granularity = SMARTAuthGranularity.patientSelectNative

	public init() {}
}

/// Enum describing the desired granularity of the authorize flow.
public enum SMARTAuthGranularity: Sendable {
	case tokenOnly
	case launchContext
	case patientSelectWeb
	case patientSelectNative
}

/// A client instance handles authentication and connection to a SMART on FHIR resource server.
///
/// Create an instance of this class, then hold on to it for all your interactions with the SMART server:
///
/// ```swift
/// import SMART
///
/// let smart = Client(
///     baseURL: "https://fhir-api-dstu2.smarthealthit.org",
///     settings: [
///         //"client_id": "my_mobile_app",       // if you have one; otherwise uses dyn reg
///         "redirect": "smartapp://callback",    // must be registered in Info.plist
///     ]
/// )
/// ```
///
/// There are many other options that you can pass to `settings`, take a look at `init(baseURL:settings:)`. Also see our [programming
/// guide](https://github.com/smart-on-fhir/Swift-SMART/wiki/Client) for more information.
@MainActor
open class Client {

	/// The server this client connects to.
	public final let server: Server

	/// Set the authorize type you want, e.g. to use a built in web view for authentication and patient selection.
	open var authProperties = SMARTAuthProperties()

	/**
	Designated initializer.
	
	- parameter server: The server instance this client manages
	*/
	public init(server: Server) {
		self.server = server
		server.logger?.debug(
			"SMART",
			msg: "Initialized SMART on FHIR client against server \(server.baseURL.description)")
	}

	/**
	Use this initializer with the appropriate server/auth settings. You can use:
	
	- `client_id`:      If you have a client-id; otherwise, if the server supports OAuth2 dynamic client registration, will register itself
	- `redirect`:       After-auth redirect URL (string). Must be registered on the server and in your app's Info.plist (URL handler)
	- `redirect_uris`:  Array of redirect URL (strings); will be created if you supply "redirect"
	- `scope`:          Authorization scope, defaults to "user/\*.* openid profile" plus launch scope, if needed
	- `authorize_uri`:  Optional; if present will NOT use the authorization endpoints defined in the server's metadata. Know what you do!
	- `token_uri`:      Optional; if present will NOT use the authorization endpoints defined in the server's metadata. Know what you do!
	- `authorize_type`: Optional; inferred to be "authorization_code" or "implicit". Can also be "client_credentials" for a 2-legged
	                    OAuth2 flow.
	- `client_name`:    OPTIONAL, if you use dynamic client registration, this is the name of your app
	- `logo_uri`:       OPTIONAL, if you use dynamic client registration, a URL to the icon of your app
	
	The settings are forwarded to the `OAuth2` framework, so you can use any of the settings supported during authorization if you know
	what you're doing: `init(settings:)` from http://p2.github.io/OAuth2/Classes/OAuth2.html .
	
	- parameter baseURL:  The server's base URL
	- parameter settings: Client settings, mostly concerning authorization
	*/
	public convenience init(baseURL: URL, settings: OAuth2JSON) {
		var sett = settings
		if let redirect = settings["redirect"] as? String {
			sett["redirect_uris"] = [redirect]
		}
		if nil == settings["title"] {
			sett["title"] = "SMART"
		}
		let srv = Server(baseURL: baseURL, auth: sett)
		self.init(server: srv)
	}

	// MARK: - Preparations

	open func ready() async throws {
		try await server.ready()
	}

	/**
	Call this to start the authorization process. Implicitly calls `ready`, so no need to call it yourself.
	
	If you use the OS browser you will need to intercept the OAuth redirect in your app delegate and call `didRedirect` yourself. See
	the instructions for more detail.
	
	- parameter callback: The callback that is called when authorization finishes, with a patient resource (if launch/patient was specified
	                      or an error
	*/
	open func authorize() async throws -> Patient? {
		server.mustAbortAuthorization = false
		return try await server.authorize(with: authProperties)
	}

	open func handleEHRLaunch(
		iss: String,
		launch: String,
		additionalSettings: OAuth2JSON? = nil
	) async throws {
		guard let issuerURL = URL(string: iss) else {
			throw SMARTError.invalidIssuer(iss)
		}

		if issuerURL.absoluteString != server.baseURL.absoluteString {
			server.logger?.warn(
				"SMART",
				msg:
					"EHR launch issuer \(issuerURL.absoluteString) does not match client server URL \(server.baseURL.absoluteString)"
			)
		}

		if let additionalSettings = additionalSettings {
			if server.authSettings == nil {
				server.authSettings = additionalSettings
			} else {
				for (key, value) in additionalSettings {
					server.authSettings?[key] = value
				}
			}
		}

		try await server.ready()

		guard let auth = server.auth else {
			throw SMARTError.missingAuthorization
		}

		auth.setLaunchParameter(launch)
		if authProperties.granularity == .tokenOnly {
			authProperties.granularity = .launchContext
		}
	}

	/// Will return true while the client is waiting for the authorization callback.
	open var awaitingAuthCallback: Bool {
		return server.auth?.isAwaitingAuthorization() ?? false
	}

	/**
	Call this with the redirect URL when intercepting the redirect callback in the app delegate.
	
	- parameter url: The URL that was redirected to
	*/
	open func didRedirect(to url: URL) -> Bool {
		return server.auth?.handleRedirect(url) ?? false
	}

	/** Stops any request currently in progress. */
	open func abort() {
		server.abort()
	}

	/** Resets state and authorization data. */
	open func reset() {
		server.reset()
	}

	/** Throws away local client registration data. */
	open func forgetClientRegistration() {
		server.forgetClientRegistration()
	}

	// MARK: - Making Requests

	/**
	Request a JSON resource at the given path using the client's `FHIRClient`.
	
	- parameter path: The path relative to the server's base URL to request
	- returns: The raw FHIR response
	*/
	open func getJSON(at path: String) async throws -> FHIRClient.Response {
		let operation = RawFHIRRequestOperation(
			path: path,
			headers: ["Accept": "application/json"]
		)

		do {
			return try await server.execute(operation)
		} catch {
			if let cancellation = error.cancellationError {
				throw cancellation
			}
			throw mapError(error, forPath: path)
		}
	}

	/**
	Requests raw data against the given URL (absolute or relative to the server's base URL).
	
	- parameter url:      The URL to read data from
	- parameter accept:   The accept header to send along
	- returns: The raw FHIR response
	*/
	open func getData(from url: URL, accept: String) async throws -> FHIRClient.Response {
		let path = url.absoluteString
		let operation = RawFHIRRequestOperation(
			path: path,
			headers: ["Accept": accept]
		)

		do {
			return try await server.execute(operation)
		} catch {
			if let cancellation = error.cancellationError {
				throw cancellation
			}
			throw mapError(error, forPath: path)
		}
	}

	private func mapError(_ error: Error, forPath path: String) -> Error {
		let resolvedURL = URL(string: path, relativeTo: server.baseURL) ?? URL(string: path)
		return SMARTErrorMapper.mapPublic(error: error, url: resolvedURL)
	}

}
