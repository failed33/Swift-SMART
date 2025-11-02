import SMART
import XCTest

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

    func testClientCredentialsFlowAgainstLiveServer() throws {
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

        let readyExp = expectation(description: "Server ready")
        var readyError: Error?
        client.ready { error in
            readyError = error
            readyExp.fulfill()
        }
        wait(for: [readyExp], timeout: 15)
        XCTAssertNil(readyError, "Server readiness failed: \(String(describing: readyError))")

        // Always verify metadata endpoint
        let metadataExp = expectation(description: "GET metadata")
        client.getJSON(at: "metadata") { result in
            switch result {
            case .success(let response):
                XCTAssertTrue(response.status.isSuccessful, "metadata status: \(response.status)")
                if response.status.isSuccessful {
                    Self.printResponse(prefix: "metadata", data: response.body)
                }
                // Basic sanity check on CapabilityStatement
                if let json = try? JSONSerialization.jsonObject(with: response.body)
                    as? [String: Any]
                {
                    XCTAssertEqual(json["resourceType"] as? String, "CapabilityStatement")
                }
                metadataExp.fulfill()
            case .failure(let error):
                XCTFail("metadata request failed: \(error)")
            }
        }
        wait(for: [metadataExp], timeout: 20)

        // Optional protected query if provided (e.g., "Patient?_count=1")
        if let queryPath = env["SMART_TEST_QUERY_PATH"], !queryPath.isEmpty {
            let queryExp = expectation(description: "GET \(queryPath)")
            client.getJSON(at: queryPath) { result in
                switch result {
                case .success(let response):
                    XCTAssertTrue(response.status.isSuccessful, "query status: \(response.status)")
                    if response.status.isSuccessful {
                        Self.printResponse(prefix: queryPath, data: response.body)
                    }
                    queryExp.fulfill()
                case .failure(let error):
                    XCTFail("query failed: \(error)")
                }
            }
            wait(for: [queryExp], timeout: 30)
        }
    }
}
