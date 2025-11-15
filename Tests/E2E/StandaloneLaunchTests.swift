@preconcurrency import ModelsR5
import OAuth2
import XCTest

@testable import SMART

@MainActor
final class StandaloneLaunchTests: XCTestCase {

    func testStandaloneHappyPathPKCEPatientRead() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self)
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        let logger = context.logger

        defer { artifacts.emitAttachments() }

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )
        let authorizedPatient = outcome.patient
        let authorizeError = outcome.authorizeError
        let redirectError = outcome.redirectError
        XCTAssertNil(
            redirectError, "Redirect handling failed: \(String(describing: redirectError))")
        XCTAssertNil(authorizeError, "Authorization failed: \(String(describing: authorizeError))")
        if artifacts.authorizeURL == nil,
            let captured = await ExternalLoginDriver.takeRecordedAuthorizeURL()
        {
            artifacts.recordAuthorizeURL(captured)
        }
        if artifacts.authorizeURL == nil,
            let reconstructed = await SharedLaunchTestHelper.reconstructAuthorizeURL(from: client)
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
        guard
            let normalizedLaunchPatient = SharedLaunchTestHelper.patientReferenceComponents(
                from: launchPatient)
        else {
            XCTFail("Unable to normalize launch patient reference: \(launchPatient)")
            return
        }
        XCTAssertEqual(
            patient.id?.value?.string,
            normalizedLaunchPatient.id,
            "Patient resource identifier should match launch context identifier")

        if let auth = client.server.auth,
            let snapshot = try? await auth.withOAuth({ oauth -> OAuth2JSON in
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
                return snapshot
            })
        {
            artifacts.recordTokenResponse(snapshot)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(patient) {
            artifacts.recordPatientData(data)
        }
    }

    func testStandaloneAuthorizeFailsWithoutAud() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self,
            transform: { url in
                self.removingQueryItem(named: "aud", from: url)
            })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )
        let patient = outcome.patient
        let authorizeError = outcome.authorizeError
        let redirectError = outcome.redirectError

        XCTAssertNil(patient)
        XCTAssertNil(redirectError, "Expected server to redirect with error payload")
        guard let error = authorizeError else {
            XCTFail("Expected authorization error when aud parameter is omitted")
            return
        }

        let messages = errorMessageCandidates(artifacts: artifacts, error: error)
        let mentionsMissingAudience = messages.contains { message in
            message.contains("aud") || message.contains("audience") || message.contains("resource")
        }
        XCTAssertTrue(
            mentionsMissingAudience,
            "Error should mention missing aud parameter. Observed messages: \(messages)")

        if let redirect = artifacts.redirectURL,
            let components = URLComponents(url: redirect, resolvingAgainstBaseURL: false)
        {
            let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value
            XCTAssertNotNil(errorParam, "Expected authorization server to provide error parameter")
        }
    }

    func testStandaloneAuthorizeFailsWithPlainPKCE() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self,
            transform: { url in
                self.replacingQueryItem(name: "code_challenge_method", value: "plain", in: url)
            })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )
        let patient = outcome.patient
        let authorizeError = outcome.authorizeError
        let redirectError = outcome.redirectError

        XCTAssertNil(patient)
        XCTAssertNil(redirectError, "Expected server to redirect with PKCE error payload")
        guard let error = authorizeError else {
            XCTFail("Expected authorization error when PKCE method is plain")
            return
        }

        let messages = errorMessageCandidates(artifacts: artifacts, error: error)
        let mentionsPKCE = messages.contains { message in
            message.contains("pkce") || message.contains("code_challenge")
                || message.contains("code challenge")
        }
        XCTAssertTrue(
            mentionsPKCE,
            "Error should mention PKCE failure. Observed messages: \(messages)")

        if let redirect = artifacts.redirectURL,
            let components = URLComponents(url: redirect, resolvingAgainstBaseURL: false)
        {
            let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value
            XCTAssertNotNil(errorParam, "Expected PKCE failure to surface via error parameter")
        }
    }

    func testStandaloneStateMismatchDetected() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self)
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts,
            mutateRedirect: { url in self.tamperingState(in: url) },
            expectRedirectHandled: false
        )

        let patient = outcome.patient
        let authorizeError = outcome.authorizeError
        let redirectError = outcome.redirectError

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

    func testStandaloneMissingPatientContextHandledGracefully() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self,
            configureOAuth: { oauth in
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

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )
        let patient = outcome.patient
        let authorizeError = outcome.authorizeError
        let redirectError = outcome.redirectError

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

    func testStandaloneRefreshTokenFlow() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self)
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )
        let patient = outcome.patient
        let authorizeError = outcome.authorizeError
        let redirectError = outcome.redirectError

        XCTAssertNil(redirectError)
        XCTAssertNil(authorizeError)
        guard let auth = client.server.auth,
            try await auth.withOAuth({ $0.clientConfig.refreshToken != nil }) == true
        else {
            throw XCTSkip("Server did not issue a refresh token")
        }

        let oauth = try await auth.withOAuth { $0 }
        guard let launchPatient = client.server.launchContext?.patient else {
            throw XCTSkip("Authorization server did not supply patient context")
        }
        guard
            let normalizedLaunchPatient = SharedLaunchTestHelper.patientReferenceComponents(
                from: launchPatient)
        else {
            XCTFail("Unable to normalize launch patient reference: \(launchPatient)")
            return
        }

        let initialAccessToken = oauth.clientConfig.accessToken
        let refreshExpectation = expectation(description: "Token refresh completes")
        var refreshError: OAuth2Error?
        oauth.doRefreshToken { _, error in
            refreshError = error
            refreshExpectation.fulfill()
        }
        await fulfillment(of: [refreshExpectation], timeout: 30)
        XCTAssertNil(
            refreshError, "Refresh token exchange failed: \(String(describing: refreshError))")
        XCTAssertNotEqual(oauth.clientConfig.accessToken, initialAccessToken)

        let refreshedPatient = try await client.server.readPatient(id: normalizedLaunchPatient.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(refreshedPatient) {
            artifacts.recordPatientData(data)
        }

        if let patient {
            XCTAssertEqual(patient.id?.value?.string, normalizedLaunchPatient.id)
            XCTAssertEqual(refreshedPatient.id?.value?.string, normalizedLaunchPatient.id)
        }
    }

    func testStandaloneDiscoveryCacheRespectsForceRefresh() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self)
        let client = context.client
        let artifacts = context.artifacts
        defer { artifacts.emitAttachments() }

        let configuration = try await client.server.getSMARTConfiguration(forceRefresh: false)
        if let recorded = artifacts.configuration {
            XCTAssertEqual(configuration.authorizationEndpoint, recorded.authorizationEndpoint)
            XCTAssertEqual(configuration.tokenEndpoint, recorded.tokenEndpoint)
        }

        let refreshed = try await client.server.getSMARTConfiguration(forceRefresh: true)
        if let recorded = artifacts.configuration {
            XCTAssertEqual(refreshed.authorizationEndpoint, recorded.authorizationEndpoint)
            XCTAssertEqual(refreshed.tokenEndpoint, recorded.tokenEndpoint)
        }
    }

    func testStandaloneRejectsMismatchedRedirect() async throws {
        let context = try await SharedLaunchTestHelper.prepareStandaloneClient(
            testCase: self,
            transform: { url in
                self.bumpRedirectPort(in: url)
            })
        let client = context.client
        let artifacts = context.artifacts
        let callbackListener = context.callback
        defer { artifacts.emitAttachments() }

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts,
            redirectTimeout: 30
        )

        XCTAssertNil(outcome.patient)
        guard let redirectError = outcome.redirectError else {
            XCTFail("Expected redirect listener to time out for mismatched redirect")
            return
        }

        if let listenerError = redirectError as? CallbackListener.ListenerError {
            switch listenerError {
            case .timedOut:
                break
            default:
                XCTFail("Unexpected redirect error: \(listenerError)")
            }
        }

        if let authorizeError = outcome.authorizeError {
            let isCancellation = authorizeError is CancellationError
            let isOAuth2Error = authorizeError as? OAuth2Error != nil
            XCTAssertTrue(
                isCancellation || isOAuth2Error,
                "Unexpected authorize error: \(authorizeError)")
        }
    }

    private func errorMessageCandidates(
        artifacts: StandaloneLaunchHelper.Artifacts,
        error: Error
    ) -> [String] {
        var messages: [String] = []
        if let redirectDescription = redirectErrorDescription(from: artifacts) {
            messages.append(redirectDescription.lowercased())
        }
        messages.append(String(describing: error).lowercased())
        return messages
    }

    private func redirectErrorDescription(
        from artifacts: StandaloneLaunchHelper.Artifacts
    ) -> String? {
        redirectQueryItem(named: "error_description", artifacts: artifacts)
    }

    private func redirectQueryItem(
        named name: String,
        artifacts: StandaloneLaunchHelper.Artifacts
    ) -> String? {
        guard let redirect = artifacts.redirectURL,
            let components = URLComponents(url: redirect, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        guard let value = components.queryItems?.first(where: { $0.name == name })?.value else {
            return nil
        }
        return value.removingURLEncoding()
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

extension String {
    fileprivate func removingURLEncoding() -> String {
        let plusAsSpace = replacingOccurrences(of: "+", with: " ")
        return plusAsSpace.removingPercentEncoding ?? plusAsSpace
    }
}
