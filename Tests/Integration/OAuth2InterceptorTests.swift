@testable import SMART
import OAuth2
import XCTest

final class OAuth2InterceptorTests: XCTestCase {
    private func makeAuth(accessToken: String?) -> Auth {
        let server = Server(baseURL: URL(string: "https://example.org/fhir")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)
        let oauth = OAuth2CodeGrant(settings: [
            "client_id": "test",
            "authorize_uri": "https://example.org/authorize",
            "token_uri": "https://example.org/token",
            "redirect_uris": ["app://callback"]
        ])
        oauth.accessToken = accessToken
        auth.oauth = oauth
        return auth
    }

    func testAddsAuthorizationHeaderWhenAccessTokenPresent() async throws {
        let auth = makeAuth(accessToken: "abc123")
        let interceptor = OAuth2BearerInterceptor(auth: auth)

        var request = URLRequest(url: URL(string: "https://example.org/fhir/Patient/1")!)
        request.httpMethod = "GET"

        let chain = MockChain(request: request)
        _ = try await interceptor.interceptAsync(chain: chain)

        let modified = try XCTUnwrap(chain.modifiedRequest)
        XCTAssertEqual(modified.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testDoesNotAddAuthorizationHeaderWhenTokenMissing() async throws {
        let auth = makeAuth(accessToken: nil)
        let interceptor = OAuth2BearerInterceptor(auth: auth)

        var request = URLRequest(url: URL(string: "https://example.org/fhir/Patient/1")!)
        request.httpMethod = "GET"

        let chain = MockChain(request: request)
        _ = try await interceptor.interceptAsync(chain: chain)

        let modified = try XCTUnwrap(chain.modifiedRequest)
        XCTAssertNil(modified.value(forHTTPHeaderField: "Authorization"))
    }
}

