import Foundation
import HTTPClient

final class MockChain: Chain {
    var request: URLRequest
    private(set) var modifiedRequest: URLRequest?
    private(set) var proceedCallCount: Int = 0

    var nextResponse: HTTPResponse?
    var nextError: HTTPClientError?

    init(request: URLRequest) {
        self.request = request
    }

    func proceedAsync(request: URLRequest) async throws -> HTTPResponse {
        modifiedRequest = request
        proceedCallCount += 1

        if let error = nextError {
            throw error
        }

        if let response = nextResponse {
            return response
        }

        return Self.defaultResponse(for: request)
    }

    // MARK: - Helpers

    private static func defaultResponse(for request: URLRequest) -> HTTPResponse {
        let url = request.url ?? URL(string: "https://mock.local")!
        let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(), httpResponse, .ok)
    }
}

