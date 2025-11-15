@preconcurrency import ModelsR5
import OAuth2
import XCTest

@testable import SMART

enum SharedLaunchTestHelper {

    struct PreparedClientContext {
        let environment: StandaloneLaunchHelper.Environment
        let client: Client
        let artifacts: StandaloneLaunchHelper.Artifacts
        let callback: CallbackListener
        let authorizer: AutomationAuthorizer
        let logger: StandaloneLaunchHelper.CapturingOAuth2Logger
    }

    struct AuthorizationOutcome {
        let patient: ModelsR5.Patient?
        let authorizeError: Error?
        let redirectError: Error?
    }

    private struct AuthorizationTaskResult: @unchecked Sendable {
        let patient: ModelsR5.Patient?
    }

    @MainActor
    static func prepareStandaloneClient(
        testCase: XCTestCase,
        transform: ((URL) -> URL)? = nil,
        configureAuthProperties: ((inout SMARTAuthProperties) -> Void)? = nil,
        configureOAuth: ((OAuth2) -> Void)? = nil
    ) async throws -> PreparedClientContext {
        let environment = try StandaloneLaunchHelper.Environment.load()
        let artifacts = StandaloneLaunchHelper.Artifacts()

        var redirectComponents =
            environment.registeredRedirect.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            } ?? URLComponents()
        let resolvedScheme: String
        if let scheme = redirectComponents.scheme, !scheme.isEmpty {
            resolvedScheme = scheme
        } else {
            resolvedScheme = "http"
        }
        redirectComponents.scheme = resolvedScheme

        let resolvedHost =
            redirectComponents.host?.isEmpty == false ? redirectComponents.host! : "127.0.0.1"
        redirectComponents.host = resolvedHost

        var resolvedPath = redirectComponents.path
        if resolvedPath.isEmpty {
            resolvedPath = "/callback"
        } else if !resolvedPath.hasPrefix("/") {
            resolvedPath = "/\(resolvedPath)"
        }
        redirectComponents.path = resolvedPath

        let preferredPort = redirectComponents.port
        let requestedPort: UInt16
        let enforceRequestedPort: Bool
        if let preferredPort, preferredPort > 0 {
            guard preferredPort <= Int(UInt16.max) else {
                XCTFail("SMART_REDIRECT specifies port outside UInt16 range: \(preferredPort)")
                throw NSError(
                    domain: "SharedLaunchTestHelper",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey: "SMART_REDIRECT port \(preferredPort) is invalid"
                    ]
                )
            }
            requestedPort = UInt16(preferredPort)
            enforceRequestedPort = true
        } else {
            requestedPort = 0
            enforceRequestedPort = false
        }

        let callbackListener = CallbackListener(
            host: resolvedHost,
            port: requestedPort,
            path: resolvedPath
        )
        try callbackListener.start()
        let portDeadline = Date().addingTimeInterval(2)
        while callbackListener.port == 0 && Date() < portDeadline {
            try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }
        guard callbackListener.port != 0 else {
            XCTFail("Callback listener failed to bind to a loopback port")
            throw NSError(
                domain: "SharedLaunchTestHelper",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Callback listener did not report a port"]
            )
        }
        if enforceRequestedPort && callbackListener.port != requestedPort {
            callbackListener.stop()
            let message =
                "Callback listener bound to port \(callbackListener.port) instead of requested \(requestedPort)"
            XCTFail(message)
            throw NSError(
                domain: "SharedLaunchTestHelper",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        testCase.addTeardownBlock {
            callbackListener.stop()
        }

        redirectComponents.port = Int(callbackListener.port)
        guard let redirectURI = redirectComponents.url?.absoluteString else {
            let message = "Failed to construct redirect URI from SMART_REDIRECT components"
            XCTFail(message)
            throw NSError(
                domain: "SharedLaunchTestHelper",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        let client = StandaloneLaunchHelper.makeClient(
            environment: environment, redirect: redirectURI)

        var authProps = SMARTAuthProperties()
        authProps.embedded = false
        authProps.granularity = .tokenOnly
        configureAuthProperties?(&authProps)
        client.authProperties = authProps

        let logger = StandaloneLaunchHelper.CapturingOAuth2Logger()
        client.server.logger = logger

        try await client.ready()

        guard let auth = client.server.auth else {
            XCTFail("OAuth configuration missing after readiness")
            throw NSError(
                domain: "SharedLaunchTestHelper",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "OAuth configuration missing after readiness"]
            )
        }

        let oauth = try await auth.withOAuth { oauth -> OAuth2 in
            oauth.logger = logger
            configureOAuth?(oauth)
            oauth.useKeychain = false
            oauth.forgetTokens()
            return oauth
        }
        let authorizer = AutomationAuthorizer(
            oauth2: oauth,
            didOpenURL: { url in
                artifacts.recordAuthorizeURL(url)
            }, transform: transform)
        oauth.authorizer = authorizer

        let configuration = try await client.server.getSMARTConfiguration(forceRefresh: false)
        artifacts.recordConfiguration(configuration)
        StandaloneLaunchHelper.assertSupportsPKCES256(configuration)

        let actualAuthorize = oauth.clientConfig.authorizeURL
        XCTAssertEqual(
            actualAuthorize,
            configuration.authorizationEndpoint,
            "OAuth authorize URL must match SMART discovery"
        )

        return PreparedClientContext(
            environment: environment,
            client: client,
            artifacts: artifacts,
            callback: callbackListener,
            authorizer: authorizer,
            logger: logger
        )
    }

    @MainActor
    static func executeAuthorization(
        client: Client,
        callbackListener: CallbackListener,
        artifacts: StandaloneLaunchHelper.Artifacts,
        redirectTimeout: TimeInterval = 90,
        mutateRedirect: ((URL) -> URL)? = nil,
        expectRedirectHandled: Bool = true
    ) async -> AuthorizationOutcome {
        let authorizeTask = _Concurrency.Task<AuthorizationTaskResult, Error> { @MainActor in
            let patient = try await client.authorize()
            return AuthorizationTaskResult(patient: patient)
        }

        var redirectError: Error?
        var capturedRedirect: URL?

        do {
            capturedRedirect = try await callbackListener.awaitRedirect(timeout: redirectTimeout)
        } catch {
            redirectError = error
        }

        if let redirectURL = capturedRedirect {
            let finalURL = mutateRedirect?(redirectURL) ?? redirectURL
            artifacts.recordRedirectURL(finalURL)
            let handled = client.didRedirect(to: finalURL)
            if !handled && expectRedirectHandled {
                redirectError = NSError(
                    domain: "SharedLaunchTestHelper",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Client did not accept redirect URL"
                    ]
                )
            }
        } else {
            client.abort()
            authorizeTask.cancel()
        }

        var authorizeError: Error?
        var patient: ModelsR5.Patient?

        do {
            let result = try await authorizeTask.value
            patient = result.patient
        } catch {
            authorizeError = error
        }

        return AuthorizationOutcome(
            patient: patient,
            authorizeError: authorizeError,
            redirectError: redirectError
        )
    }

    @MainActor
    static func reconstructAuthorizeURL(from client: Client) async -> URL? {
        guard let auth = client.server.auth else { return nil }
        return try? await auth.withOAuth { oauth -> URL? in
            guard let redirect = oauth.redirect ?? oauth.clientConfig.redirect else { return nil }

            var components = URLComponents(url: oauth.authURL, resolvingAgainstBaseURL: false)
            var mergedItems = components?.queryItems ?? []
            var existingNames = Set(mergedItems.map { $0.name })

            func addParam(_ name: String, _ value: String?) {
                guard let value, !value.isEmpty else { return }
                if existingNames.contains(name) {
                    mergedItems.removeAll { $0.name == name }
                    existingNames.remove(name)
                }
                mergedItems.append(URLQueryItem(name: name, value: value))
                existingNames.insert(name)
            }

            addParam("redirect_uri", redirect)
            addParam("state", oauth.context.state)
            addParam("client_id", oauth.clientId)
            if let responseType = type(of: oauth).responseType {
                addParam("response_type", responseType)
            }
            addParam("scope", oauth.scope)
            if oauth.clientConfig.useProofKeyForCodeExchange {
                addParam("code_challenge", oauth.context.codeChallenge())
                addParam("code_challenge_method", oauth.context.codeChallengeMethod)
            }
            if let authParameters = oauth.authParameters {
                for (key, value) in authParameters {
                    addParam(key, value)
                }
            }
            if let customParameters = oauth.clientConfig.customParameters {
                for (key, value) in customParameters {
                    addParam(key, value)
                }
            }
            addParam("aud", client.server.aud)
            if let launch = auth.launchParameter(), !launch.isEmpty {
                addParam("launch", launch)
            }

            components?.queryItems = mergedItems.isEmpty ? nil : mergedItems
            return components?.url
        }
    }

    struct PatientReferenceComponents: Equatable {
        let resourceType: String
        let id: String

        var reference: String {
            "\(resourceType)/\(id)"
        }
    }

    static func patientReferenceComponents(
        from rawReference: String?
    ) -> PatientReferenceComponents? {
        guard let rawReference else { return nil }
        let trimmed = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let segments = trimmed.split(separator: "/").filter { !$0.isEmpty }
        guard let idSegment = segments.last else { return nil }

        let resourceTypeSegment: String
        if segments.count >= 2 {
            resourceTypeSegment = String(segments[segments.count - 2])
        } else {
            resourceTypeSegment = "Patient"
        }

        let canonicalType = canonicalResourceType(resourceTypeSegment)
        return PatientReferenceComponents(resourceType: canonicalType, id: String(idSegment))
    }

    static func canonicalPatientReference(from rawReference: String?) -> String? {
        patientReferenceComponents(from: rawReference)?.reference
    }

    static func patientID(from rawReference: String?) -> String? {
        patientReferenceComponents(from: rawReference)?.id
    }

    private static func canonicalResourceType(_ raw: String) -> String {
        let lowercase = raw.lowercased()
        guard let first = lowercase.first else { return "Patient" }
        let firstCharacter = String(first).uppercased()
        let remainder = lowercase.dropFirst()
        return firstCharacter + remainder
    }
}
