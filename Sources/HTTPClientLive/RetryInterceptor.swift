import Foundation
import HTTPClient

public final class RetryInterceptor: Interceptor {
    private let policy: RetryPolicy
    private let sleepHandler: (TimeInterval) async throws -> Void

    public init(
        policy: RetryPolicy = RetryPolicy(),
        sleepHandler: @escaping (TimeInterval) async throws -> Void = RetryInterceptor.defaultSleep
    ) {
        self.policy = policy
        self.sleepHandler = sleepHandler
    }

    public func interceptAsync(chain: Chain) async throws -> HTTPResponse {
        var attempt = 0
        let originalRequest = chain.request

        while true {
            do {
                let response = try await chain.proceedAsync(request: originalRequest)
                if let directive = policy.directiveForResponse(
                    statusCode: response.status.rawValue,
                    method: originalRequest.httpMethod,
                    retryAfterHeader: response.response.value(forHTTPHeaderField: "Retry-After"),
                    attempt: attempt
                ) {
                    try await sleepHandler(directive.delay)
                    attempt += 1
                    continue
                }
                return response
            } catch let error as HTTPClientError {
                if case .httpError(let urlError) = error,
                    let directive = policy.directiveForError(
                        urlError, method: originalRequest.httpMethod, attempt: attempt)
                {
                    try await sleepHandler(directive.delay)
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    public static func defaultSleep(_ delay: TimeInterval) async throws {
        guard delay > 0 else { return }
        let nanoseconds = UInt64(delay * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
