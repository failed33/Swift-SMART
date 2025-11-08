import Foundation
import HTTPClient
import OAuth2
import XCTest

@testable import SMART

@MainActor
final class AuthRefreshInterceptorTests: XCTestCase {
    private func makeAuth() -> Auth {
        let server = Server(
            baseURL: URL(string: "https://example.org")!, httpClient: MockHTTPClient())
        return Auth(
            type: .codeGrant,
            server: server,
            aud: server.aud,
            initialLogger: nil,
            settings: nil,
            uiHandler: TestAuthUIHandler()
        )
    }

    func testPerformsRefreshOnInvalidTokenChallenge() async throws {
        let auth = makeAuth()
        let oauth = MockOAuth2()
        oauth.forceTokenExpiration = true
        oauth.nextResult = (["access_token": "fresh-token"], nil)
        auth.replaceOAuthForTesting(oauth)

        let interceptor = AuthRefreshInterceptor(auth: auth)

        var request = URLRequest(url: URL(string: "https://example.org/patient")!)
        request.httpMethod = "GET"
        request.setValue("Bearer stale-token", forHTTPHeaderField: "Authorization")

        let unauthorized = TestHTTPResponseFactory.make(
            status: .unauthorized,
            url: request.url!,
            headers: ["WWW-Authenticate": "Bearer error=\"invalid_token\""]
        )
        let success = TestHTTPResponseFactory.make(status: .ok, url: request.url!, headers: [:])

        let chain = SequencedChain(
            request: request, results: [.success(unauthorized), .success(success)])

        let response = try await interceptor.interceptAsync(chain: chain)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(chain.proceedCallCount, 2)
        XCTAssertEqual(oauth.tryCallCount, 1)
        XCTAssertEqual(
            chain.recordedRequests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-token"
        )
    }

    func testStopsRetryAfterSecondUnauthorized() async throws {
        let auth = makeAuth()
        let oauth = MockOAuth2()
        oauth.forceTokenExpiration = true
        oauth.nextResult = (["access_token": "fresh-token"], nil)
        auth.replaceOAuthForTesting(oauth)

        let interceptor = AuthRefreshInterceptor(auth: auth)

        var request = URLRequest(url: URL(string: "https://example.org/patient")!)
        request.httpMethod = "GET"
        request.setValue("Bearer stale-token", forHTTPHeaderField: "Authorization")

        let unauthorized = TestHTTPResponseFactory.make(
            status: .unauthorized,
            url: request.url!,
            headers: ["WWW-Authenticate": "Bearer error=\"invalid_token\""]
        )

        let chain = SequencedChain(
            request: request, results: [.success(unauthorized), .success(unauthorized)])

        let response = try await interceptor.interceptAsync(chain: chain)

        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(chain.proceedCallCount, 2)
        XCTAssertEqual(oauth.tryCallCount, 1)
    }

    func testInsufficientScopeDoesNotTriggerRefresh() async throws {
        let auth = makeAuth()
        let oauth = MockOAuth2()
        oauth.forceTokenExpiration = true
        auth.replaceOAuthForTesting(oauth)

        let interceptor = AuthRefreshInterceptor(auth: auth)

        let url = URL(string: "https://example.org/patient")!
        let request = URLRequest(url: url)

        let insufficientScope = TestHTTPResponseFactory.make(
            status: .unauthorized,
            url: url,
            headers: ["WWW-Authenticate": "Bearer error=\"insufficient_scope\""]
        )

        let chain = SequencedChain(request: request, results: [.success(insufficientScope)])

        let response = try await interceptor.interceptAsync(chain: chain)

        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(chain.proceedCallCount, 1)
        XCTAssertEqual(oauth.tryCallCount, 0)
    }
}
