import Foundation
import OAuth2
import SMART
import XCTest

enum StandaloneLaunchHelper {

    static let defaultScope = "launch/patient patient/*.rs openid fhirUser offline_access"

    struct Environment {
        let baseURL: URL
        let clientId: String
        let scope: String
        let registeredRedirect: URL?
        let user: String?
        let password: String?

        static func load(processInfo: ProcessInfo = .processInfo) throws -> Environment {
            let env = processInfo.environment

            guard let baseString = env["SMART_BASE_URL"], let baseURL = URL(string: baseString)
            else {
                throw XCTSkip("SMART_BASE_URL not set; skipping standalone launch tests")
            }
            guard let clientId = env["SMART_CLIENT_ID"], !clientId.isEmpty else {
                throw XCTSkip("SMART_CLIENT_ID not set; skipping standalone launch tests")
            }

            let scope = StandaloneLaunchHelper.resolveScope(env["SMART_SCOPE"])
            let registeredRedirect = env["SMART_REDIRECT"].flatMap { URL(string: $0) }

            return Environment(
                baseURL: baseURL,
                clientId: clientId,
                scope: scope,
                registeredRedirect: registeredRedirect,
                user: env["SMART_USER"],
                password: env["SMART_PASSWORD"]
            )
        }
    }

    final class CapturingOAuth2Logger: OAuth2Logger {

        var level: OAuth2LogLevel
        private let underlying: OAuth2Logger
        private(set) var lastAuthorizeURL: URL?

        init(level: OAuth2LogLevel = .debug, underlying: OAuth2Logger = OAuth2DebugLogger(.debug)) {
            self.level = level
            self.underlying = underlying
        }

        func log(
            _ atLevel: OAuth2LogLevel,
            module: String?,
            filename: String?,
            line: Int?,
            function: String?,
            msg: @autoclosure () -> String
        ) {
            underlying.log(
                atLevel, module: module, filename: filename, line: line, function: function,
                msg: msg())
        }

        func trace(
            _ module: String?,
            filename: String?,
            line: Int?,
            function: String?,
            msg: @autoclosure () -> String
        ) {
            underlying.trace(module, filename: filename, line: line, function: function, msg: msg())
        }

        func debug(
            _ module: String?,
            filename: String?,
            line: Int?,
            function: String?,
            msg: @autoclosure () -> String
        ) {
            let message = msg()
            recordAuthorizeURLIfPresent(in: message)
            underlying.debug(
                module, filename: filename, line: line, function: function, msg: message)
        }

        func warn(
            _ module: String?,
            filename: String?,
            line: Int?,
            function: String?,
            msg: @autoclosure () -> String
        ) {
            underlying.warn(module, filename: filename, line: line, function: function, msg: msg())
        }

        private func recordAuthorizeURLIfPresent(in message: String) {
            guard let range = message.range(of: "http", options: .caseInsensitive) else { return }
            let substring = message[range.lowerBound...]
            if let url = URL(string: String(substring)) {
                lastAuthorizeURL = url
            }
        }
    }

    final class Artifacts {
        var configuration: SMARTConfiguration?
        var authorizeURL: URL?
        var redirectURL: URL?
        var tokenResponse: OAuth2JSON?
        var patientData: Data?

        func recordConfiguration(_ configuration: SMARTConfiguration) {
            self.configuration = configuration
        }

        func recordAuthorizeURL(_ url: URL) {
            authorizeURL = url
        }

        func recordRedirectURL(_ url: URL) {
            redirectURL = url
        }

        func recordTokenResponse(_ json: OAuth2JSON) {
            tokenResponse = json
        }

        func recordPatientData(_ data: Data) {
            patientData = data
        }

        @MainActor
        func emitAttachments() {
            XCTContext.runActivity(named: "Standalone Launch Artifacts") { activity in
                if let configuration {
                    let attachment = XCTAttachment(
                        data: encode(configuration), uniformTypeIdentifier: "public.json")
                    attachment.name = "smart-configuration.json"
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
                if let authorizeURL {
                    let attachment = XCTAttachment(string: authorizeURL.absoluteString)
                    attachment.name = "authorize-url.txt"
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
                if let redirectURL {
                    let attachment = XCTAttachment(string: redirectURL.absoluteString)
                    attachment.name = "redirect-url.txt"
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
                if let tokenResponse,
                    let data = sanitize(json: tokenResponse)
                {
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "token-response.json"
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
                if let patientData,
                    let string = String(data: patientData, encoding: .utf8)
                {
                    let attachment = XCTAttachment(string: string)
                    attachment.name = "patient.json"
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
            }
        }

        private func encode(_ configuration: SMARTConfiguration) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? encoder.encode(configuration)) ?? Data()
        }

        private func sanitize(json: OAuth2JSON) -> Data? {
            var sanitized = json
            let sensitiveKeys: Set<String> = [
                "access_token", "refresh_token", "id_token", "client_secret",
            ]
            for key in sensitiveKeys where sanitized[key] != nil {
                sanitized[key] = "<redacted>"
            }
            return try? JSONSerialization.data(
                withJSONObject: sanitized,
                options: [.prettyPrinted, .sortedKeys]
            )
        }
    }

    @MainActor
    static func makeClient(
        environment: Environment,
        redirect: String?,
        additionalSettings: OAuth2JSON = [:]
    ) -> Client {
        var settings: OAuth2JSON = [
            "client_id": environment.clientId,
            "scope": environment.scope,
            "authorize_type": "authorization_code",
        ]
        if let redirect {
            settings["redirect"] = redirect
        } else if let registered = environment.registeredRedirect?.absoluteString {
            settings["redirect"] = registered
        }
        for (key, value) in additionalSettings {
            settings[key] = value
        }
        return Client(baseURL: environment.baseURL, settings: settings)
    }

    static func resolveScope(_ raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultScope
        }
        return raw
    }

    static func assertSupportsPKCES256(
        _ configuration: SMARTConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let methods = configuration.codeChallengeMethodsSupported ?? []
        let supports = methods.contains { $0.caseInsensitiveCompare("S256") == .orderedSame }
        XCTAssertTrue(
            supports,
            "SMART configuration must advertise code_challenge_methods_supported that contain S256",
            file: file,
            line: line
        )
    }
}
