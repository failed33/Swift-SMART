import Foundation
import HTTPClient

final class SequencedChain: Chain {
    var request: URLRequest

    private var results: [Result<HTTPResponse, HTTPClientError>]
    private(set) var proceedCallCount = 0
    private(set) var recordedRequests: [URLRequest] = []

    init(request: URLRequest, results: [Result<HTTPResponse, HTTPClientError>]) {
        self.request = request
        self.results = results
    }

    func proceedAsync(request: URLRequest) async throws -> HTTPResponse {
        proceedCallCount += 1
        recordedRequests.append(request)

        guard !results.isEmpty else {
            throw HTTPClientError.internalError("SequencedChain ran out of stubbed results")
        }

        let next = results.removeFirst()
        switch next {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}


