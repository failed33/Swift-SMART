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
import Security

/// A simple implementation of an HTTP client using the interceptor concept.
public class DefaultHTTPClient: HTTPClient {
    public let interceptors: [Interceptor]
    private let urlSession: URLSession

    private weak var delegate: ProxyDelegate?

    /// Initializer for the lightweight HTTP client
    ///
    /// - Parameters:
    ///   - urlSession: `URLSessionConfiguration` that is used to create the URLSession.
    ///   - interceptors: list of `Interceptors` that may modify the request and/or response before sending.
    ///   - delegateQueue: An operation queue for scheduling the delegate calls and completion handlers.
    ///   - allowInsecureConnections: If `true`, accepts self-signed certificates for localhost. **FOR DEVELOPMENT ONLY**.
    public init(
        urlSessionConfiguration: URLSessionConfiguration,
        interceptors: [Interceptor] = [],
        delegateQueue: OperationQueue? = nil,
        allowInsecureConnections: Bool = false
    ) {
        let delegate = ProxyDelegate(allowInsecureConnections: allowInsecureConnections)

        // [REQ:gemSpec_Krypt:GS-A_4385,A_18467,A_18464,GS-A_4387]
        // [REQ:gemSpec_IDP_Frontend:A_20606#2] Setup of minimum TLS Version to use.
        // [REQ:gemSpec_eRp_FdV:A_20206]
        // [REQ:BSI-eRp-ePA:O.Ntwk_2#2,O.Ntwk_3#2,O.Ntwk_7#2] URLSession is used as Network Framework
        urlSessionConfiguration.tlsMinimumSupportedProtocolVersion = .TLSv12
        urlSession = .init(
            configuration: urlSessionConfiguration, delegate: delegate, delegateQueue: delegateQueue
        )
        self.interceptors = interceptors
        self.delegate = delegate
    }

    /// Send the given request. The request will be processed by the list of `Interceptors`.
    ///
    /// - Parameter request: The request to be (modified and) sent.
    /// - Returns: `AnyPublisher` that emits a response as `URLSessionResponse`
    public func sendPublisher(
        request: URLRequest,
        interceptors requestInterceptors: [Interceptor],
        redirect handler: RedirectHandler?
    ) -> AnyPublisher<HTTPResponse, HTTPClientError> {
        let requestID = UUID().uuidString
        let newRequest = request.add(requestID: requestID)
        let delegate = self.delegate
        let combinedInterceptors = interceptors + requestInterceptors

        return URLRequestChain(request: newRequest, session: urlSession, with: combinedInterceptors)
            .proceedPublisher(request: newRequest)
            .handleEvents(
                receiveSubscription: { _ in
                    guard let delegate else { return }
                    Task {
                        await delegate.setRedirectHandler(handler, for: requestID)
                    }
                },
                receiveCompletion: { _ in
                    guard let delegate else { return }
                    Task {
                        await delegate.setRedirectHandler(nil, for: requestID)
                    }
                },
                receiveCancel: {
                    guard let delegate else { return }
                    Task {
                        await delegate.setRedirectHandler(nil, for: requestID)
                    }
                }
            )
            .eraseToAnyPublisher()
    }

    public func sendAsync(
        request: URLRequest,
        interceptors requestInterceptors: [Interceptor],
        redirect handler: RedirectHandler?
    ) async throws -> HTTPResponse {
        let requestID = UUID().uuidString
        let newRequest = request.add(requestID: requestID)
        let delegate = self.delegate

        await delegate?.setRedirectHandler(handler, for: requestID)
        let chain = URLRequestChain(
            request: newRequest,
            session: urlSession,
            with: interceptors + requestInterceptors
        )

        do {
            let response = try await chain.proceedAsync(request: newRequest)
            await delegate?.setRedirectHandler(nil, for: requestID)
            return response
        } catch {
            await delegate?.setRedirectHandler(nil, for: requestID)
            throw error
        }
    }
}

extension URLRequest {
    func add(requestID: String) -> URLRequest {
        var modifiedRequest = self
        modifiedRequest.addValue(requestID, forHTTPHeaderField: "X-RID")
        return modifiedRequest
    }
}

extension DefaultHTTPClient {
    actor ProxyDelegate: NSObject, URLSessionTaskDelegate {
        private var redirectHandler = [String: RedirectHandler]()
        private let allowInsecureConnections: Bool

        init(allowInsecureConnections: Bool = false) {
            self.allowInsecureConnections = allowInsecureConnections
        }

        func setRedirectHandler(_ handler: RedirectHandler?, for identifier: String) async {
            redirectHandler[identifier] = handler
        }

        func urlSession(
            _: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            if let originalRequest = task.originalRequest,
                let requestID = originalRequest.value(forHTTPHeaderField: "X-RID"),
                let handler = redirectHandler[requestID]
            {
                return await handler(response, request)
            }
            return request
        }

        nonisolated func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler:
                @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard allowInsecureConnections else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            // Only bypass certificate validation for localhost-style hosts
            let host = challenge.protectionSpace.host.lowercased()
            let isLoopbackHost = host == "localhost" || host == "127.0.0.1" || host == "::1"
            let isLocalhostAlias = host.hasSuffix(".localhost")

            guard isLoopbackHost || isLocalhostAlias else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            if challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
                let serverTrust = challenge.protectionSpace.serverTrust
            {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
