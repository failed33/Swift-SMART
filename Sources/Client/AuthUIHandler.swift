import Foundation
import OAuth2

/// Abstraction that bridges UI responsibilities for SMART authorization flows.
///
/// Implementers are typically platform-specific types (iOS, macOS) that know how to present the
/// appropriate UI on the main actor. All UI-facing methods are isolated to `@MainActor` to make the
/// required thread-hopping explicit to call sites.
public protocol AuthUIHandler: Sendable {

    /// Presents the primary web authentication session and returns the redirect URL on success.
    @MainActor
    func presentAuthSession(
        startURL: URL,
        callbackScheme: String,
        oauth: OAuth2
    ) async throws -> URL

    /// Cancels any ongoing authentication session presentation, if possible.
    @MainActor
    func cancelOngoingAuthSession()

    /// Presents native patient selection UI when required and returns the enriched parameters.
    @MainActor
    func presentPatientSelector(
        server: Server,
        parameters: OAuth2JSON,
        oauth: OAuth2
    ) async throws -> OAuth2JSON
}

