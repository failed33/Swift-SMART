import Foundation
import OAuth2
import _Concurrency

public enum AuthorizationOutcome: @unchecked Sendable {
    case success(OAuth2JSON)
    case failure(OAuth2Error)
}

/// Main-actor type responsible for encapsulating mutable authentication state and OAuth2
/// interactions.
///
/// This type is the single source of truth for data that must not be accessed concurrently from
/// multiple tasks, such as the `OAuth2` instance and launch context information returned from the
/// SMART authorization servers. All access should happen through the asynchronous APIs exposed
/// below to ensure serialized access and predictable ordering.
@MainActor
public final class AuthCore {

    // MARK: - Stored State

    private var oauth: OAuth2?
    private var launchContext: LaunchContext?
    private var launchParameter: String?
    private var logger: OAuth2Logger?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        oauth: OAuth2? = nil,
        launchContext: LaunchContext? = nil,
        launchParameter: String? = nil,
        logger: OAuth2Logger? = nil
    ) {
        self.oauth = oauth
        self.launchContext = launchContext
        self.launchParameter = launchParameter
        self.logger = logger

        self.oauth?.logger = logger
    }

    // MARK: - OAuth2 Lifecycle

    public func updateOAuth(_ oauth: OAuth2?) {
        self.oauth = oauth
        self.oauth?.logger = logger
    }

    public func currentOAuth() -> OAuth2? {
        oauth
    }

    public func updateLogger(_ logger: OAuth2Logger?) {
        self.logger = logger
        oauth?.logger = logger
    }

    public func configure(scope: String) {
        oauth?.scope = scope
    }

    public func hasUnexpiredToken() -> Bool {
        oauth?.hasUnexpiredAccessToken() ?? false
    }

    public func handleRedirect(_ url: URL) throws {
        guard let oauth else {
            throw SMARTError.missingAuthorization
        }
        try oauth.handleRedirectURL(url)
    }

    public func forgetTokens() {
        oauth?.forgetTokens()
    }

    public func forgetClient() {
        oauth?.forgetClient()
    }

    public func signedRequest(forURL url: URL) -> URLRequest? {
        oauth?.request(forURL: url)
    }

    // MARK: - Launch Context

    public func updateLaunchContext(_ context: LaunchContext?) {
        launchContext = context
    }

    public func currentLaunchContext() -> LaunchContext? {
        launchContext
    }

    public func updateLaunchParameter(_ parameter: String?) {
        launchParameter = parameter
    }

    public func currentLaunchParameter() -> String? {
        launchParameter
    }

    public func parseLaunchContext(from parameters: OAuth2JSON) -> LaunchContext? {
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
            return try decoder.decode(LaunchContext.self, from: data)
        } catch {
            logger?.warn("SMART", msg: "Failed to parse launch context: \(error)")
            return nil
        }
    }

    public func encodeLaunchContext(_ context: LaunchContext) -> [String: Any]? {
        do {
            let data = try encoder.encode(context)
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            logger?.warn("SMART", msg: "Failed to encode launch context: \(error)")
            return nil
        }
    }

    public func currentAccessToken() -> String? {
        oauth?.accessToken
    }

    public func updateAccessToken(_ token: String?) {
        oauth?.accessToken = token
    }

    public func currentIDToken() -> String? {
        oauth?.idToken
    }

    public func currentRefreshToken() -> String? {
        oauth?.refreshToken
    }

    public func authorizeURL(params: OAuth2StringDict?) throws -> URL {
        guard let oauth else {
            throw SMARTError.missingAuthorization
        }
        return try oauth.authorizeURL(params: params)
    }

    public func setAuthorizationCallback(
        _ handler: @escaping @Sendable (OAuth2JSON?, OAuth2Error?) -> Void
    ) {
        oauth?.didAuthorizeOrFail = handler
    }

    public func clearAuthorizationCallback() {
        oauth?.didAuthorizeOrFail = nil
    }

    public func setDynamicClientRegistrationHandler(
        _ handler: (@Sendable (URL) -> OAuth2DynReg?)?
    ) {
        oauth?.onBeforeDynamicClientRegistration = handler
    }

    public func openAuthorizeURLInBrowser(_ url: URL) throws {
        guard let oauth else {
            throw SMARTError.missingAuthorization
        }
        try oauth.authorizer.openAuthorizeURLInBrowser(url)
    }

    public func abortAuthorization() {
        oauth?.abortAuthorization()
    }

    public func redirectScheme() -> String? {
        if let redirect = oauth?.redirect, !redirect.isEmpty {
            return redirect
        }
        return oauth?.clientConfig.redirect
    }

    public func withOAuth<Result>(
        _ operation: @MainActor @Sendable (OAuth2) async throws -> Result
    ) async throws -> Result {
        guard let oauth else {
            throw SMARTError.missingAuthorization
        }
        return try await operation(oauth)
    }

    private var authorizationContinuation: AsyncStream<AuthorizationOutcome>.Continuation?

    public func waitForAuthorization() -> AsyncStream<AuthorizationOutcome> {
        AsyncStream<AuthorizationOutcome> { continuation in
            self.authorizationContinuation = continuation

            continuation.onTermination = { [weak self] reason in
                guard let self else { return }
                _Concurrency.Task {
                    await self.authorizationStreamDidTerminate(reason: reason)
                }
            }

            // Set up the OAuth callback
            self.oauth?.didAuthorizeOrFail = { parameters, error in
                if let error {
                    continuation.yield(AuthorizationOutcome.failure(error))
                } else {
                    continuation.yield(AuthorizationOutcome.success(parameters ?? [:]))
                }
                continuation.finish()
            }
        }
    }

    public func cancelAuthorization() {
        finishAuthorization(shouldAbort: false)
    }

    public func terminateAuthorization() {
        finishAuthorization(shouldAbort: true)
    }

    private func finishAuthorization(shouldAbort: Bool) {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        clearAuthorizationCallback()
        continuation?.finish()

        if shouldAbort {
            oauth?.abortAuthorization()
        }
    }

    private func authorizationStreamDidTerminate(
        reason: AsyncStream<AuthorizationOutcome>.Continuation.Termination
    ) async {
        authorizationContinuation = nil
        clearAuthorizationCallback()

        if case .cancelled = reason {
            oauth?.abortAuthorization()
        }
    }
}
