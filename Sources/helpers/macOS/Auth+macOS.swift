//
//  Client+iOS.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/25/14.
//  Copyright (c) 2014 SMART Health IT. All rights reserved.
//

#if os(macOS)
	import AppKit
	import AuthenticationServices
	import Cocoa
	import OAuth2

	@MainActor
	public final class macOSAuthUIHandler: NSObject, AuthUIHandler,
		ASWebAuthenticationPresentationContextProviding
	{

		public typealias AnchorProvider = @Sendable @MainActor () -> NSWindow?

		private let anchorProvider: AnchorProvider
		private var activeSession: ASWebAuthenticationSession?

		public init(
			anchorProvider: @escaping AnchorProvider = macOSAuthUIHandler
				.defaultAnchorProviderClosure
		) {
			self.anchorProvider = anchorProvider
		}

		// MARK: - AuthUIHandler

		public func presentAuthSession(
			startURL: URL,
			callbackScheme: String,
			oauth: OAuth2
		) async throws -> URL {
			try await withTaskCancellationHandler {
				try await withCheckedThrowingContinuation { continuation in
					let session = ASWebAuthenticationSession(
						url: startURL,
						callbackURLScheme: callbackScheme
					) { [weak self] url, error in
						_Concurrency.Task { @MainActor [weak self] in
							self?.activeSession = nil
						}
						if let url {
							continuation.resume(returning: url)
						} else {
							let underlying = error ?? CancellationError()
							continuation.resume(throwing: underlying)
						}
					}

					session.presentationContextProvider = self

					guard session.start() else {
						continuation.resume(
							throwing: SMARTError.generic("Failed to start authentication session."))
						return
					}

					self.activeSession = session
				}
			} onCancel: {
				_Concurrency.Task { @MainActor in
					self.cancelOngoingAuthSession()
				}
			}
		}

		public func presentPatientSelector(
			server: Server,
			parameters: OAuth2JSON,
			oauth: OAuth2
		) async throws -> OAuth2JSON {
			throw SMARTError.generic("Native patient selection is not available on macOS.")
		}

		public func cancelOngoingAuthSession() {
			activeSession?.cancel()
			activeSession = nil
		}

		// MARK: - ASWebAuthenticationPresentationContextProviding

		public func presentationAnchor(for session: ASWebAuthenticationSession)
			-> ASPresentationAnchor
		{
			anchorProvider() ?? NSApplication.shared.keyWindow ?? ASPresentationAnchor()
		}

		// MARK: - Helpers

		public static let defaultAnchorProviderClosure: AnchorProvider = {
			NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
		}
	}

#endif
