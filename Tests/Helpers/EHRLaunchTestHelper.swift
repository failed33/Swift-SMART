import Darwin
import Foundation
import XCTest

@testable import SMART

enum EHRLaunchTestHelper {

    struct Environment {
        let issuer: URL
        let keycloakBase: URL
        let realm: String
        let authorizeEndpoint: URL
        let tokenEndpoint: URL
        let contextEndpoint: URL
        let clientId: String
        let scope: String
        let redirectURL: URL
        let patientReference: String
        let intent: String?
        let tenant: String?
        let schemaURL: URL
        let templateURL: URL
        let automationEndpoint: String?
        let requestTimeout: TimeInterval
    }

    struct ContextCreationResult {
        let environment: Environment
        let contextId: String
        let patientReference: String
        let payload: Data
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let scope: String?
        let token_type: String?
    }

    private struct ContextResponse: Decodable {
        let context_id: String
    }

    private static let defaultSchema = URL(
        string:
            "https://raw.githubusercontent.com/zedwerks/keycloak-smart-fhir/main/context-schema/launch-context_v1.json"
    )!

    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()  // Helpers
        url.deleteLastPathComponent()  // Tests
        return url.deletingLastPathComponent()  // Swift-SMART
    }()

    static func loadEnvironment(processInfo: ProcessInfo = .processInfo) throws -> Environment {
        let env = processInfo.environment

        guard let issuerString = env["SMART_EHR_ISS"],
            let issuer = URL(string: issuerString)
        else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 10,
                userInfo: [
                    NSLocalizedDescriptionKey: "SMART_EHR_ISS must be set to the FHIR base URL"
                ]
            )
        }

        let keycloakBaseString = env["SMART_EHR_KEYCLOAK_BASE"] ?? "https://keycloak.localhost"
        guard let keycloakBase = URL(string: keycloakBaseString) else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 11,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "SMART_EHR_KEYCLOAK_BASE must be a valid URL: \(keycloakBaseString)"
                ]
            )
        }

        let realm = env["SMART_EHR_REALM"] ?? "smart"
        let oidcBase =
            keycloakBase
            .appendingPathComponent("realms")
            .appendingPathComponent(realm)
            .appendingPathComponent("protocol")
            .appendingPathComponent("openid-connect")
        let authorizeEndpoint = oidcBase.appendingPathComponent("auth")
        let tokenEndpoint = oidcBase.appendingPathComponent("token")

        let contextEndpointString =
            env["SMART_EHR_CONTEXT_URL"]
            ?? keycloakBase
            .appendingPathComponent("realms")
            .appendingPathComponent(realm)
            .appendingPathComponent("smart-on-fhir")
            .appendingPathComponent("context")
            .absoluteString
        guard let contextEndpoint = URL(string: contextEndpointString) else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 12,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "SMART_EHR_CONTEXT_URL must be a valid URL: \(contextEndpointString)"
                ]
            )
        }

        let clientId = env["SMART_EHR_CLIENT_ID"] ?? "demo-emr"
        let scope = env["SMART_EHR_SCOPE"] ?? "openid Context.write"

        let redirectString = env["SMART_EHR_REDIRECT"] ?? "http://127.0.0.1:8765/emr-callback"
        guard let redirectURL = URL(string: redirectString) else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 13,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "SMART_EHR_REDIRECT must be a valid URL: \(redirectString)"
                ]
            )
        }

        guard
            let patientRaw =
                env["SMART_EHR_PATIENT"] ?? env["SMART_EHR_PATIENT_REFERENCE"],
            !patientRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 14,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Provide SMART_EHR_PATIENT (e.g., Patient/123) so the launch context can be created"
                ]
            )
        }
        let patientReference = normalizePatientReference(patientRaw)

        let schemaURL =
            (env["SMART_EHR_CONTEXT_SCHEMA_URL"].flatMap { URL(string: $0) }) ?? defaultSchema

        let templatePath =
            env["SMART_EHR_LAUNCH_TEMPLATE"]
            ?? repoRoot.appendingPathComponent("Tests/Fixtures/launch-context.json").path
        let templateURL = URL(fileURLWithPath: templatePath)

        let automationEndpoint = env["SMART_EHR_AUTOMATION_ENDPOINT"]
        let timeout =
            env["SMART_EHR_REDIRECT_TIMEOUT"].flatMap { TimeInterval($0) } ?? 180

        return Environment(
            issuer: issuer,
            keycloakBase: keycloakBase,
            realm: realm,
            authorizeEndpoint: authorizeEndpoint,
            tokenEndpoint: tokenEndpoint,
            contextEndpoint: contextEndpoint,
            clientId: clientId,
            scope: scope,
            redirectURL: redirectURL,
            patientReference: patientReference,
            intent: env["SMART_EHR_INTENT"],
            tenant: env["SMART_EHR_TENANT"],
            schemaURL: schemaURL,
            templateURL: templateURL,
            automationEndpoint: automationEndpoint,
            requestTimeout: timeout
        )
    }

    @MainActor
    static func createLaunchContext(
        testCase: XCTestCase,
        environment: Environment? = nil
    ) async throws -> ContextCreationResult {
        let env = try environment ?? loadEnvironment()
        let accessToken = try await obtainPractitionerToken(testCase: testCase, environment: env)
        let payload = try buildLaunchPayload(environment: env)
        let contextId = try await postLaunchContext(
            environment: env,
            payload: payload,
            accessToken: accessToken
        )
        return ContextCreationResult(
            environment: env,
            contextId: contextId,
            patientReference: env.patientReference,
            payload: payload
        )
    }

    // MARK: - OAuth Helpers

    @MainActor
    private static func obtainPractitionerToken(
        testCase: XCTestCase,
        environment: Environment
    ) async throws -> String {
        let automationOverride = AutomationEndpointOverride(
            urlString: environment.automationEndpoint)
        defer { automationOverride.restore() }

        let redirectComponents = try RedirectComponents(url: environment.redirectURL)
        let listener = CallbackListener(
            host: redirectComponents.host,
            port: redirectComponents.port,
            path: redirectComponents.path
        )
        try listener.start()
        defer { listener.stop() }

        let pkce = PKCE.generate()
        let state = UUID().uuidString

        var authorize = URLComponents(
            url: environment.authorizeEndpoint,
            resolvingAgainstBaseURL: false
        )
        authorize?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: environment.clientId),
            URLQueryItem(name: "redirect_uri", value: environment.redirectURL.absoluteString),
            URLQueryItem(name: "scope", value: environment.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]

        guard let authorizeURL = authorize?.url else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Failed to build authorize URL"]
            )
        }

        try ExternalLoginDriver.open(authorizeURL)

        let redirectURL = try await listener.awaitRedirect(timeout: environment.requestTimeout)
        guard let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Authorization redirect missing code/state"]
            )
        }

        guard returnedState == state else {
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 22,
                userInfo: [NSLocalizedDescriptionKey: "State mismatch during practitioner login"]
            )
        }

        let bodyItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: environment.redirectURL.absoluteString),
            URLQueryItem(name: "client_id", value: environment.clientId),
            URLQueryItem(name: "code_verifier", value: pkce.codeVerifier),
        ]
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = bodyItems

        var request = URLRequest(url: environment.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 23,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Token endpoint returned \( (response as? HTTPURLResponse)?.statusCode ?? -1): \(bodyText)"
                ]
            )
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return token.access_token
    }

    // MARK: - Launch Context

    private static func buildLaunchPayload(environment: Environment) throws -> Data {
        var object: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: environment.templateURL.path) {
            let data = try Data(contentsOf: environment.templateURL)
            object = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }

        object["resourceType"] = object["resourceType"] ?? "LaunchContext"
        object["$schema"] = environment.schemaURL.absoluteString
        object["patient"] = environment.patientReference

        if let intent = environment.intent {
            object["intent"] = intent
        }
        if let tenant = environment.tenant {
            object["tenant"] = tenant
        }

        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func postLaunchContext(
        environment: Environment,
        payload: Data,
        accessToken: String
    ) async throws -> String {
        var request = URLRequest(url: environment.contextEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = payload

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            throw NSError(
                domain: "EHRLaunchTestHelper",
                code: 24,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Context endpoint returned \( (response as? HTTPURLResponse)?.statusCode ?? -1): \(bodyText)"
                ]
            )
        }
        let context = try JSONDecoder().decode(ContextResponse.self, from: data)
        return context.context_id
    }

    // MARK: - Utilities

    private struct RedirectComponents {
        let host: String
        let port: UInt16
        let path: String

        init(url: URL) throws {
            guard let host = url.host else {
                throw NSError(
                    domain: "EHRLaunchTestHelper",
                    code: 30,
                    userInfo: [
                        NSLocalizedDescriptionKey: "SMART_EHR_REDIRECT must include a host"
                    ]
                )
            }
            self.host = host
            if let value = url.port {
                guard value > 0 && value <= Int(UInt16.max) else {
                    throw NSError(
                        domain: "EHRLaunchTestHelper",
                        code: 31,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "SMART_EHR_REDIRECT port must be within UInt16 range"
                        ]
                    )
                }
                self.port = UInt16(value)
            } else {
                self.port = 0
            }
            let rawPath = url.path.isEmpty ? "/callback" : url.path
            self.path = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        }
    }

    private static func normalizePatientReference(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return trimmed
        }
        if trimmed.contains("/") {
            return trimmed
        }
        return "Patient/\(trimmed)"
    }
    private struct AutomationEndpointOverride {
        let previousValue: String?
        let shouldRestore: Bool

        init(urlString: String?) {
            if let urlString {
                previousValue = getenv("SMART_AUTOMATION_ENDPOINT").flatMap { String(cString: $0) }
                setenv("SMART_AUTOMATION_ENDPOINT", urlString, 1)
                shouldRestore = true
            } else {
                previousValue = nil
                shouldRestore = false
            }
        }

        func restore() {
            guard shouldRestore else { return }
            if let previousValue {
                setenv("SMART_AUTOMATION_ENDPOINT", previousValue, 1)
            } else {
                unsetenv("SMART_AUTOMATION_ENDPOINT")
            }
        }
    }
}
