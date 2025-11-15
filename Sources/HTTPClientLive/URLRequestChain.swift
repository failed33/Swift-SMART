//
//  Copyright (Change Date see Readme), gematik GmbH
//
//  Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the
//  European Commission – subsequent versions of the EUPL (the "Licence").
//  You may not use this work except in compliance with the Licence.
//
//  You find a copy of the Licence in the "Licence" file or at
//  https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the Licence is distributed on an "AS IS" basis,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either expressed or implied.
//  In case of changes by gematik find details in the "Readme" file.
//
//  See the Licence for the specific language governing permissions and limitations under the Licence.
//
//  *******
//
// For additional notes and disclaimer from gematik and in case of changes by gematik find details in the "Readme" file.
//

import Combine
import Foundation
import HTTPClient

final class URLRequestChain: Chain, @unchecked Sendable {
    var request: URLRequest
    private let session: URLSession
    private let interceptors: [Interceptor]

    init(request: URLRequest, session: URLSession, with interceptors: [Interceptor]) {
        self.session = session
        self.request = request
        self.interceptors = interceptors
    }

    func proceedAsync(request newRequest: URLRequest) async throws -> HTTPResponse {
        request = newRequest
        if let interceptor = interceptors.first {
            let nextChain = URLRequestChain(
                request: newRequest,
                session: session,
                with: Array(interceptors.dropFirst())
            )
            return try await interceptor.interceptAsync(chain: nextChain)
        } else {
            // interceptors is empty
            let data: Data
            let urlResponse: URLResponse
            do {
                (data, urlResponse) = try await session.data(for: newRequest, delegate: nil)
            } catch {
                throw error.asHTTPClientError()
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw HTTPClientError.internalError("URLResponse is not a HTTPURLResponse")
            }
            guard let statusCode = HTTPStatusCode(rawValue: httpResponse.statusCode) else {
                throw HTTPClientError.internalError(
                    "Unsupported http status code [\(httpResponse.statusCode)]")
            }
            return (data: data, response: httpResponse, status: statusCode)
        }
    }
}

extension URLRequestChain {
    func proceedPublisher(request newRequest: URLRequest) -> AnyPublisher<
        HTTPResponse, HTTPClientError
    > {
        Deferred {
            Future { promise in
                let promiseBox = HTTPResponsePromiseBox(promise)
                _Concurrency.Task {
                    do {
                        let response = try await self.proceedAsync(request: newRequest)
                        promiseBox.succeed(with: response)
                    } catch let error as HTTPClientError {
                        promiseBox.fail(with: error)
                    } catch {
                        promiseBox.fail(with: error.asHTTPClientError())
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

private final class HTTPResponsePromiseBox: @unchecked Sendable {
    private let promise: Future<HTTPResponse, HTTPClientError>.Promise

    init(_ promise: @escaping Future<HTTPResponse, HTTPClientError>.Promise) {
        self.promise = promise
    }

    func succeed(with response: HTTPResponse) {
        promise(.success(response))
    }

    func fail(with error: HTTPClientError) {
        promise(.failure(error))
    }
}
