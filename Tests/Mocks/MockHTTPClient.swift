import Foundation
import HTTPClient

final class MockHTTPClient: HTTPClient {
    struct ResponseConfiguration {
        var data: Data
        var statusCode: Int
        var headers: [String: String]

        init(
            data: Data = Data(),
            statusCode: Int = HTTPStatusCode.ok.rawValue,
            headers: [String: String] = ["Content-Type": "application/json"]
        ) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
        }
    }

    var interceptors: [Interceptor] = []

    private(set) var recordedRequests: [URLRequest] = []
    var responseDelay: TimeInterval = 0
    var shouldFail: Bool = false
    var failureError: HTTPClientError = .networkError("MockHTTPClient configured to fail")

    var mockResponses: [String: ResponseConfiguration] = [:]

    func sendAsync(
        request: URLRequest,
        interceptors: [Interceptor],
        redirect handler: RedirectHandler?
    ) async throws -> HTTPResponse {
        let response = try prepareResponse(for: request)
        if responseDelay > 0 {
            let nanoseconds = UInt64(responseDelay * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        return response
    }

    // MARK: - Helpers

    func setResponse(
        for url: URL,
        data: Data,
        statusCode: Int = HTTPStatusCode.ok.rawValue,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        mockResponses[url.path] = ResponseConfiguration(
            data: data, statusCode: statusCode, headers: headers)
    }

    func clearRecordedRequests() {
        recordedRequests.removeAll()
    }

    func lastRequest() -> URLRequest? {
        recordedRequests.last
    }

    func requestCount(for path: String) -> Int {
        recordedRequests.filter { $0.url?.path == path }.count
    }

    func hasAuthorizationHeader(in request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "Authorization")?.isEmpty == false
    }

    private func prepareResponse(for request: URLRequest) throws -> HTTPResponse {
        recordedRequests.append(request)

        if shouldFail {
            throw failureError
        }

        guard let url = request.url else {
            throw HTTPClientError.internalError("MockHTTPClient received request without URL")
        }

        guard let configuration = mockResponses[url.path] else {
            throw HTTPClientError.networkError("Mock response not configured for \(url.path)")
        }

        guard
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: configuration.statusCode,
                httpVersion: nil,
                headerFields: configuration.headers
            )
        else {
            throw HTTPClientError.internalError("Failed to build HTTPURLResponse for \(url)")
        }

        let status = HTTPStatusCode(rawValue: configuration.statusCode) ?? .ok
        return (configuration.data, httpResponse, status)
    }

}
