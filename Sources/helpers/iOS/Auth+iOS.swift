//
//  Client+iOS.swift
//  SMART-on-FHIR
//
//  Created by Pascal Pfiffner on 6/25/14.
//  Copyright (c) 2014 SMART Health IT. All rights reserved.
//

// TODO: This uses the old UIKit framework, we need to migrate to the new SwiftUI framework, especially since the old shenanigans with ViewControlers are highly unreliable. iOS 26 introduced some new embedded browsing feature we need to look up and then implement an auth flow via that interface.
import _Concurrency

#if os(iOS)
	import AuthenticationServices
	import UIKit
	import OAuth2

	@MainActor
	public final class iOSAuthUIHandler: NSObject, AuthUIHandler,
		ASWebAuthenticationPresentationContextProviding
	{

		public typealias AnchorProvider = () -> UIWindow?

		private let anchorProvider: AnchorProvider
		private weak var activePresenter: UIViewController?
		private var activeSession: ASWebAuthenticationSession?

		public init(
			anchorProvider: @escaping AnchorProvider = iOSAuthUIHandler.defaultAnchorProvider
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
					Task { @MainActor [weak self] in
						guard let self else {
							continuation.resume(throwing: CancellationError())
							return
						}

						let session = ASWebAuthenticationSession(
							url: startURL,
							callbackURLScheme: callbackScheme
						) { [weak self] url, error in
							Task { @MainActor in
								guard let self else { return }
								self.activeSession = nil
								if let url {
									continuation.resume(returning: url)
								} else {
									let underlying = error ?? CancellationError()
									continuation.resume(throwing: underlying)
								}
							}
						}

						session.presentationContextProvider = self
						guard session.start() else {
							continuation.resume(
								throwing: SMARTError.generic(
									"Failed to start authentication session."))
							return
						}

						self.activeSession = session
					}
				}
			} onCancel: {
				Task { @MainActor [weak self] in
					self?.activeSession?.cancel()
					self?.activeSession = nil
				}
			}
		}

		public func presentPatientSelector(
			server: Server,
			parameters: OAuth2JSON,
			oauth: OAuth2
		) async throws -> OAuth2JSON {
			try await withTaskCancellationHandler {
				try await withCheckedThrowingContinuation { continuation in
					Task { @MainActor [weak self] in
						guard let self else {
							continuation.resume(throwing: CancellationError())
							return
						}

						guard let presenter = self.topPresenter() else {
							continuation.resume(
								throwing: OAuth2Error.invalidAuthorizationContext)
							return
						}

						let patientList = PatientListViewController(
							list: PatientListAll(), server: server)
						patientList.title = oauth.authConfig.ui.title
						var resumed = false

						patientList.onPatientSelect = { [weak self, weak patientList] patient in
							Task { @MainActor in
								guard let self else { return }
								guard !resumed else { return }
								resumed = true

								self.activePresenter = nil

								if let patient {
									var enriched = parameters
									enriched["patient"] = patient.id
									enriched["patient_resource"] = patient
									continuation.resume(returning: enriched)
								} else {
									continuation.resume(throwing: CancellationError())
								}

								if let patientList,
									patientList.isBeingPresented
										|| patientList.presentingViewController != nil
								{
									patientList.dismiss(animated: true)
								}
							}
						}

						let navigation = UINavigationController(rootViewController: patientList)
						navigation.modalPresentationStyle = .formSheet

						self.activePresenter = presenter
						presenter.present(navigation, animated: true, completion: nil)
					}
				}
			} onCancel: {
				Task { @MainActor [weak self] in
					self?.activePresenter?.presentedViewController?.dismiss(animated: true)
					self?.activePresenter = nil
				}
			}
		}

		public func cancelOngoingAuthSession() {
			activeSession?.cancel()
			activeSession = nil

			if let presenter = activePresenter, let controller = presenter.presentedViewController {
				controller.dismiss(animated: true)
			}
			activePresenter = nil
		}

		// MARK: - ASWebAuthenticationPresentationContextProviding

		public func presentationAnchor(for session: ASWebAuthenticationSession)
			-> ASPresentationAnchor
		{
			anchorProvider() ?? ASPresentationAnchor()
		}

		// MARK: - Helpers

		public static func defaultAnchorProvider() -> UIWindow? {
			if let keyWindow = UIApplication.shared.connectedScenes
				.compactMap({ $0 as? UIWindowScene })
				.flatMap({ $0.windows })
				.first(where: { $0.isKeyWindow })
			{
				return keyWindow
			}
			return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
		}

		private func topPresenter() -> UIViewController? {
			guard let window = anchorProvider() else { return nil }
			return topViewController(startingFrom: window.rootViewController)
		}

		private func topViewController(startingFrom controller: UIViewController?)
			-> UIViewController?
		{
			if let navigation = controller as? UINavigationController {
				return topViewController(startingFrom: navigation.visibleViewController)
			}
			if let tab = controller as? UITabBarController {
				return topViewController(startingFrom: tab.selectedViewController)
			}
			if let presented = controller?.presentedViewController {
				return topViewController(startingFrom: presented)
			}
			return controller
		}
	}

#endif
