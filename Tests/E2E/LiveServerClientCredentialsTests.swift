import Foundation
import SMART
import XCTest

@MainActor
final class LiveServerClientCredentialsTests: XCTestCase {

    private static func printResponse(prefix: String, data: Data) {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            print("\(prefix) response JSON: \(object)")
        } else if let string = String(data: data, encoding: .utf8) {
            print("\(prefix) response UTF-8: \(string)")
        } else {
            print("\(prefix) response (base64): \(data.base64EncodedString())")
        }
    }

    func testClientCredentialsFlowAgainstLiveServer() async throws {
        let env = ProcessInfo.processInfo.environment

        guard let base = env["SMART_BASE_URL"], let baseURL = URL(string: base) else {
            throw XCTSkip("SMART_BASE_URL not set; skipping live server test")
        }
        guard let clientId = env["SMART_CLIENT_ID"], !clientId.isEmpty else {
            throw XCTSkip("SMART_CLIENT_ID not set; skipping live server test")
        }
        guard let clientSecret = env["SMART_CLIENT_SECRET"], !clientSecret.isEmpty else {
            throw XCTSkip("SMART_CLIENT_SECRET not set; skipping live server test")
        }

        let scope = env["SMART_SCOPE"] ?? "system/*.rs"

        let client = Client(
            baseURL: baseURL,
            settings: [
                "client_id": clientId,
                "client_secret": clientSecret,
                "authorize_type": "client_credentials",
                "scope": scope,
            ]
        )

        try await client.ready()

        // Always verify metadata endpoint
        let metadataResponse = try await client.getJSON(at: "metadata")
        XCTAssertTrue(
            metadataResponse.status.isSuccessful, "metadata status: \(metadataResponse.status)")
        if metadataResponse.status.isSuccessful {
            Self.printResponse(prefix: "metadata", data: metadataResponse.body)
        }
        if let json = try? JSONSerialization.jsonObject(with: metadataResponse.body)
            as? [String: Any]
        {
            XCTAssertEqual(json["resourceType"] as? String, "CapabilityStatement")
        }

        // Optional protected query if provided (e.g., "Patient?_count=1")
        if let queryPath = env["SMART_TEST_QUERY_PATH"], !queryPath.isEmpty {
            let response = try await client.getJSON(at: queryPath)
            XCTAssertTrue(response.status.isSuccessful, "query status: \(response.status)")
            if response.status.isSuccessful {
                Self.printResponse(prefix: queryPath, data: response.body)
            }
        }
    }
}
