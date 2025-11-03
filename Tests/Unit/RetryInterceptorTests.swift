@testable import HTTPClientLive
import Foundation
import HTTPClient
import XCTest

final class RetryInterceptorTests: XCTestCase {
    func testRetriesTooManyRequestsWithRetryAfter() async throws {
        let policy = RetryPolicy(maxRetries: 3, retryAfterRetries: 2)
        let recorder = SleepRecorder()
        let interceptor = RetryInterceptor(policy: policy, sleepHandler: recorder.handler())

        var request = URLRequest(url: URL(string: "https://example.org/resource")!)
        request.httpMethod = HTTPMethod.get.rawValue

        let first = TestHTTPResponseFactory.make(
            status: .tooManyRequests,
            url: request.url!,
            headers: ["Retry-After": "2"]
        )
        let second = TestHTTPResponseFactory.make(status: .ok, url: request.url!)

        let chain = SequencedChain(request: request, results: [.success(first), .success(second)])

        let response = try await interceptor.interceptAsync(chain: chain)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(chain.proceedCallCount, 2)
        XCTAssertEqual(recorder.recordedDelays, [2])
    }

    func testDoesNotRetryForPostRequests() async throws {
        let policy = RetryPolicy(maxRetries: 3)
        let recorder = SleepRecorder()
        let interceptor = RetryInterceptor(policy: policy, sleepHandler: recorder.handler())

        var request = URLRequest(url: URL(string: "https://example.org/resource")!)
        request.httpMethod = HTTPMethod.post.rawValue

        let first = TestHTTPResponseFactory.make(status: .serviceUnavailable, url: request.url!)
        let chain = SequencedChain(request: request, results: [.success(first)])

        let response = try await interceptor.interceptAsync(chain: chain)

        XCTAssertEqual(response.status, .serviceUnavailable)
        XCTAssertEqual(chain.proceedCallCount, 1)
        XCTAssertTrue(recorder.recordedDelays.isEmpty)
    }

    func testRetriesTransientURLError() async throws {
        let policy = RetryPolicy(maxRetries: 2, baseDelay: 0.5)
        let recorder = SleepRecorder()
        let interceptor = RetryInterceptor(policy: policy, sleepHandler: recorder.handler())

        var request = URLRequest(url: URL(string: "https://example.org/resource")!)
        request.httpMethod = HTTPMethod.get.rawValue

        let transientError = HTTPClientError.httpError(URLError(.timedOut))
        let success = TestHTTPResponseFactory.make(status: .ok, url: request.url!)

        let chain = SequencedChain(request: request, results: [.failure(transientError), .success(success)])

        let response = try await interceptor.interceptAsync(chain: chain)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(chain.proceedCallCount, 2)
        XCTAssertEqual(recorder.recordedDelays, [0.5])
    }
}


