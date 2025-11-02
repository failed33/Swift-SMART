import ModelsR5
import OAuth2
import XCTest

@testable import SMART

final class StandaloneLaunchTests: XCTestCase {

    func testStandaloneHappyPathPKCEPatientRead() throws {
        let context = try prepareStandaloneClient()
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        let logger = context.logger

        defer { artifacts.emitAttachments() }

        let (authorizedPatient, authorizeError, redirectError) = executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )
        XCTAssertNil(
            redirectError, "Redirect handling failed: \(String(describing: redirectError))")
        XCTAssertNil(authorizeError, "Authorization failed: \(String(describing: authorizeError))")
        if artifacts.authorizeURL == nil,
            let captured = ExternalLoginDriver.takeRecordedAuthorizeURL()
        {
            artifacts.recordAuthorizeURL(captured)
        }
        if artifacts.authorizeURL == nil,
            let reconstructed = reconstructAuthorizeURL(from: client)
        {
            artifacts.recordAuthorizeURL(reconstructed)
        }
        let capturedAuthorizeURL = artifacts.authorizeURL ?? logger.lastAuthorizeURL
        XCTAssertNotNil(capturedAuthorizeURL, "Authorize URL was not captured")
        if let capturedAuthorizeURL {
            artifacts.recordAuthorizeURL(capturedAuthorizeURL)
        }
        if let logged = logger.lastAuthorizeURL, let recorded = artifacts.authorizeURL {
            XCTAssertEqual(logged, recorded)
        }

        guard let patient = authorizedPatient else {
            XCTFail("Expected patient resource after authorization")
            return
        }

        guard let launchPatient = client.server.launchContext?.patient else {
            XCTFail("Expected launch context patient identifier")
            return
        }
        XCTAssertEqual(patient.id?.value?.string, launchPatient)

        if let oauth = client.server.auth?.oauth {
            var snapshot: OAuth2JSON = [:]
            snapshot["access_token"] =
                oauth.clientConfig.accessToken != nil ? "<redacted>" : "<missing>"
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
            artifacts.recordTokenResponse(snapshot)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(patient) {
            artifacts.recordPatientData(data)
        }
    }

    func testStandaloneAuthorizeFailsWithoutAud() throws {
        let context = try prepareStandaloneClient(transform: { url in
            self.removingQueryItem(named: "aud", from: url)
        })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let (patient, authorizeError, redirectError) = executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )

        XCTAssertNil(patient)
        XCTAssertNil(redirectError, "Expected server to redirect with error payload")
        guard let error = authorizeError else {
            XCTFail("Expected authorization error when aud parameter is omitted")
            return
        }

        let message = String(describing: error).lowercased()
        XCTAssertTrue(message.contains("aud"), "Error does not mention missing aud: \(message)")

        if let redirect = artifacts.redirectURL,
            let components = URLComponents(url: redirect, resolvingAgainstBaseURL: false)
        {
            let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value
            XCTAssertNotNil(errorParam, "Expected authorization server to provide error parameter")
        }
    }

    func testStandaloneAuthorizeFailsWithPlainPKCE() throws {
        let context = try prepareStandaloneClient(transform: { url in
            self.replacingQueryItem(name: "code_challenge_method", value: "plain", in: url)
        })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let (patient, authorizeError, redirectError) = executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )

        XCTAssertNil(patient)
        XCTAssertNil(redirectError, "Expected server to redirect with PKCE error payload")
        guard let error = authorizeError else {
            XCTFail("Expected authorization error when PKCE method is plain")
            return
        }

        let message = String(describing: error).lowercased()
        XCTAssertTrue(
            message.contains("pkce") || message.contains("code_challenge"),
            "Error does not mention PKCE: \(message)")

        if let redirect = artifacts.redirectURL,
            let components = URLComponents(url: redirect, resolvingAgainstBaseURL: false)
        {
            let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value
            XCTAssertNotNil(errorParam, "Expected PKCE failure to surface via error parameter")
        }
    }

    func testStandaloneStateMismatchDetected() throws {
        let context = try prepareStandaloneClient()
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let (patient, authorizeError, redirectError) = executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts,
            mutateRedirect: { url in self.tamperingState(in: url) },
            expectRedirectHandled: false
        )

        XCTAssertNil(patient)
        XCTAssertNil(redirectError)
        guard let error = authorizeError else {
            XCTFail("Expected authorization to fail due to state mismatch")
            return
        }

        let message = String(describing: error).lowercased()
        XCTAssertTrue(
            message.contains("state"), "Error does not mention state mismatch: \(message)")
    }

    func testStandaloneMissingPatientContextHandledGracefully() throws {
        let context = try prepareStandaloneClient(configureOAuth: { oauth in
            let originalScope = oauth.scope ?? StandaloneLaunchHelper.defaultScope
            let trimmed =
                originalScope
                .split(separator: " ")
                .filter { component in
                    let value = component.trimmingCharacters(in: .whitespaces)
                    return !value.hasPrefix("patient/") && value != "launch/patient"
                }
                .joined(separator: " ")
            oauth.scope = trimmed.isEmpty ? "openid fhirUser" : trimmed
        })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let (patient, authorizeError, redirectError) = executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )

        XCTAssertNil(redirectError)
        XCTAssertNil(authorizeError)

        if let patient {
            XCTAssertNotNil(client.server.launchContext?.patient)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(patient) {
                artifacts.recordPatientData(data)
            }
        } else {
            XCTAssertNil(client.server.launchContext?.patient)
        }
    }

    func testStandaloneRefreshTokenFlow() throws {
        let context = try prepareStandaloneClient()
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let (patient, authorizeError, redirectError) = executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )

        XCTAssertNil(redirectError)
        XCTAssertNil(authorizeError)
        guard client.server.auth?.oauth?.clientConfig.refreshToken != nil else {
            throw XCTSkip("Server did not issue a refresh token")
        }
        guard let oauth = client.server.auth?.oauth else {
            XCTFail("Missing OAuth context")
            return
        }
        guard let launchPatient = client.server.launchContext?.patient else {
            throw XCTSkip("Authorization server did not supply patient context")
        }

        let initialAccessToken = oauth.clientConfig.accessToken
        let refreshExpectation = expectation(description: "Token refresh completes")
        var refreshError: OAuth2Error?
        oauth.doRefreshToken { _, error in
            refreshError = error
            refreshExpectation.fulfill()
        }
        wait(for: [refreshExpectation], timeout: 30)
        XCTAssertNil(
            refreshError, "Refresh token exchange failed: \(String(describing: refreshError))")
        XCTAssertNotEqual(oauth.clientConfig.accessToken, initialAccessToken)

        let fetchExpectation = expectation(description: "Patient fetch after refresh")
        client.server.fetchPatient(id: launchPatient) { result in
            switch result {
            case .success(let refreshedPatient):
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(refreshedPatient) {
                    artifacts.recordPatientData(data)
                }
                fetchExpectation.fulfill()
            case .failure(let error):
                XCTFail("Patient fetch after refresh failed: \(error)")
            }
        }
        wait(for: [fetchExpectation], timeout: 30)

        if let patient {
            XCTAssertEqual(patient.id?.value?.string, launchPatient)
        }
    }

    func testStandaloneDiscoveryCacheRespectsForceRefresh() throws {
        let context = try prepareStandaloneClient()
        let client = context.client
        let artifacts = context.artifacts
        defer { artifacts.emitAttachments() }

        let cacheExpectation = expectation(description: "Discovery cached")
        client.server.getSMARTConfiguration(forceRefresh: false) { result in
            switch result {
            case .success(let configuration):
                if let recorded = artifacts.configuration {
                    XCTAssertEqual(
                        configuration.authorizationEndpoint, recorded.authorizationEndpoint)
                    XCTAssertEqual(configuration.tokenEndpoint, recorded.tokenEndpoint)
                }
                cacheExpectation.fulfill()
            case .failure(let error):
                XCTFail("Cached discovery failed: \(error)")
            }
        }
        wait(for: [cacheExpectation], timeout: 10)

        let refreshExpectation = expectation(description: "Discovery force refresh")
        client.server.getSMARTConfiguration(forceRefresh: true) { result in
            switch result {
            case .success(let refreshed):
                if let recorded = artifacts.configuration {
                    XCTAssertEqual(refreshed.authorizationEndpoint, recorded.authorizationEndpoint)
                    XCTAssertEqual(refreshed.tokenEndpoint, recorded.tokenEndpoint)
                }
                refreshExpectation.fulfill()
            case .failure(let error):
                XCTFail("Force refresh failed: \(error)")
            }
        }
        wait(for: [refreshExpectation], timeout: 10)
    }

    func testStandaloneRejectsMismatchedRedirect() throws {
        let context = try prepareStandaloneClient(transform: { url in
            self.bumpRedirectPort(in: url)
        })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let authorizeExpectation = expectation(description: "Authorization callback after abort")
        var authorizeError: Error?
        client.authorize { _, error in
            authorizeError = error
            authorizeExpectation.fulfill()
        }

        let timeoutExpectation = expectation(description: "Loopback redirect timeout")
        var redirectError: Error?
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try callbackListener.awaitRedirect(timeout: 30)
                timeoutExpectation.fulfill()
            } catch {
                redirectError = error
                timeoutExpectation.fulfill()
            }
        }

        wait(for: [timeoutExpectation], timeout: 35)
        XCTAssertNotNil(
            redirectError, "Expected redirect listener to time out for mismatched redirect")
        if let listenerError = redirectError as? CallbackListener.ListenerError {
            switch listenerError {
            case .timedOut:
                break
            default:
                XCTFail("Unexpected redirect error: \(listenerError)")
            }
        }

        client.abort()
        wait(for: [authorizeExpectation], timeout: 10)
        XCTAssertNil(authorizeError)
    }

    @discardableResult
    private func executeAuthorization(
        client: Client,
        callbackListener: CallbackListener,
        artifacts: StandaloneLaunchHelper.Artifacts,
        redirectTimeout: TimeInterval = 90,
        mutateRedirect: ((URL) -> URL)? = nil,
        expectRedirectHandled: Bool = true
    ) -> (ModelsR5.Patient?, Error?, Error?) {
        let authorizeExpectation = expectation(description: "Authorization completes")
        var authorizeError: Error?
        var authorizedPatient: ModelsR5.Patient?
        client.authorize { patient, error in
            authorizeError = error
            authorizedPatient = patient
            authorizeExpectation.fulfill()
        }

        let redirectExpectation = expectation(description: "Loopback redirect received")
        var redirectError: Error?
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let redirectURL = try callbackListener.awaitRedirect(timeout: redirectTimeout)
                DispatchQueue.main.async {
                    let finalURL = mutateRedirect?(redirectURL) ?? redirectURL
                    artifacts.recordRedirectURL(finalURL)
                    if !client.didRedirect(to: finalURL) && expectRedirectHandled {
                        redirectError = NSError(
                            domain: "StandaloneLaunchTests",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Client did not accept redirect URL"
                            ]
                        )
                    }
                    redirectExpectation.fulfill()
                }
            } catch {
                redirectError = error
                redirectExpectation.fulfill()
            }
        }

        wait(for: [redirectExpectation, authorizeExpectation], timeout: redirectTimeout + 60)
        return (authorizedPatient, authorizeError, redirectError)
    }

    private func reconstructAuthorizeURL(from client: Client) -> URL? {
        guard let auth = client.server.auth, let oauth = auth.oauth else { return nil }
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
        if let launch = auth.launchParameter, !launch.isEmpty {
            addParam("launch", launch)
        }

        components?.queryItems = mergedItems.isEmpty ? nil : mergedItems
        return components?.url
    }

    private func prepareStandaloneClient(
        transform: ((URL) -> URL)? = nil,
        configureAuthProperties: ((inout SMARTAuthProperties) -> Void)? = nil,
        configureOAuth: ((OAuth2) -> Void)? = nil
    ) throws -> (
        environment: StandaloneLaunchHelper.Environment,
        client: Client,
        artifacts: StandaloneLaunchHelper.Artifacts,
        callback: CallbackListener,
        authorizer: AutomationAuthorizer,
        logger: StandaloneLaunchHelper.CapturingOAuth2Logger
    ) {
        let environment = try StandaloneLaunchHelper.Environment.load()
        let artifacts = StandaloneLaunchHelper.Artifacts()
        let callbackListener = CallbackListener(host: "127.0.0.1", port: 0, path: "/callback")
        try callbackListener.start()
        let portDeadline = Date().addingTimeInterval(2)
        while callbackListener.port == 0 && Date() < portDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard callbackListener.port != 0 else {
            XCTFail("Callback listener failed to bind to a loopback port")
            throw NSError(
                domain: "StandaloneLaunchTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Callback listener did not report a port"]
            )
        }
        addTeardownBlock {
            callbackListener.stop()
        }

        let redirectURI = "http://127.0.0.1:\(callbackListener.port)/callback"
        let client = StandaloneLaunchHelper.makeClient(
            environment: environment, redirect: redirectURI)

        var authProps = SMARTAuthProperties()
        authProps.embedded = false
        authProps.granularity = .tokenOnly
        configureAuthProperties?(&authProps)
        client.authProperties = authProps

        let logger = StandaloneLaunchHelper.CapturingOAuth2Logger()
        client.server.logger = logger

        let readyExpectation = expectation(description: "Client ready")
        var capturedAuthorizer: AutomationAuthorizer?
        client.ready { error in
            XCTAssertNil(error, "Client readiness failed: \(String(describing: error))")
            guard let oauth = client.server.auth?.oauth else {
                XCTFail("OAuth configuration missing after readiness")
                readyExpectation.fulfill()
                return
            }

            oauth.logger = logger
            configureOAuth?(oauth)
            // TODO: For debugging/testing purpous we disable the keychain and saved tokens so we get prompted to the GUI picker every time
            oauth.useKeychain = false
            oauth.forgetTokens()
            let authorizer = AutomationAuthorizer(
                oauth2: oauth,
                didOpenURL: { url in
                    artifacts.recordAuthorizeURL(url)
                }, transform: transform)
            oauth.authorizer = authorizer
            capturedAuthorizer = authorizer

            client.server.getSMARTConfiguration(forceRefresh: false) { result in
                switch result {
                case .success(let configuration):
                    artifacts.recordConfiguration(configuration)
                    StandaloneLaunchHelper.assertSupportsPKCES256(configuration)

                    let actualAuthorize = oauth.clientConfig.authorizeURL
                    XCTAssertEqual(
                        actualAuthorize,
                        configuration.authorizationEndpoint,
                        "OAuth authorize URL must match SMART discovery"
                    )
                case .failure(let configError):
                    XCTFail("Failed to fetch cached SMART configuration: \(configError)")
                }
                readyExpectation.fulfill()
            }
        }
        wait(for: [readyExpectation], timeout: 20)

        guard let authorizer = capturedAuthorizer else {
            XCTFail("AutomationAuthorizer was not configured")
            throw NSError(
                domain: "StandaloneLaunchTests",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "AutomationAuthorizer was not configured"]
            )
        }

        return (environment, client, artifacts, callbackListener, authorizer, logger)
    }

    private func removingQueryItem(named name: String, from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        components.queryItems = items
        return components.url ?? url
    }

    private func replacingQueryItem(name: String, value: String, in url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? url
    }

    private func tamperingState(in url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        let newValue = String(UUID().uuidString.prefix(8))
        if let index = items.firstIndex(where: { $0.name == "state" }) {
            items[index] = URLQueryItem(name: "state", value: newValue)
        } else {
            items.append(URLQueryItem(name: "state", value: newValue))
        }
        components.queryItems = items
        return components.url ?? url
    }

    private func bumpRedirectPort(in url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        guard let index = items.firstIndex(where: { $0.name == "redirect_uri" }),
            let value = items[index].value,
            var redirectComponents = URLComponents(string: value)
        else {
            return url
        }

        let nextPort = (redirectComponents.port ?? 0) + 1
        redirectComponents.port = nextPort

        if let updated = redirectComponents.url?.absoluteString {
            items[index] = URLQueryItem(name: "redirect_uri", value: updated)
            components.queryItems = items
        }

        return components.url ?? url
    }
}
