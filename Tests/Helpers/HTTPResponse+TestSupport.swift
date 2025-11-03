import Foundation
import HTTPClient

enum TestHTTPResponseFactory {
    static func make(
        status: HTTPStatusCode,
        url: URL = URL(string: "https://example.org/test")!,
        headers: [String: String] = [:],
        data: Data = Data()
    ) -> HTTPResponse {
        let response = HTTPURLResponse(url: url, statusCode: status.rawValue, httpVersion: nil, headerFields: headers)!
        return (data, response, status)
    }
}


