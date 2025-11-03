//
//  OAuth2BearerInterceptor.swift
//  Swift-SMART
//
//  Injects the OAuth2 access token into outgoing HTTP requests.
//

import Combine
import Foundation
@preconcurrency import HTTPClient

final class OAuth2BearerInterceptor: Interceptor {
    weak var auth: Auth?

    init(auth: Auth?) {
        self.auth = auth
    }

    @available(*, deprecated, message: "Use interceptAsync(chain:) instead")
    func interceptPublisher(chain: Chain) -> AnyPublisher<HTTPResponse, HTTPClientError> {
        Future { [weak self] promise in
            guard let self else {
                promise(.failure(.internalError("Auth reference deallocated")))
                return
            }

            _Concurrency.Task {
                do {
                    let response = try await self.interceptAsync(chain: chain)
                    promise(.success(response))
                } catch let error as HTTPClientError {
                    promise(.failure(error))
                } catch {
                    promise(.failure(.unknown(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func interceptAsync(chain: Chain) async throws -> HTTPResponse {
        var request = chain.request

        if let token = auth?.oauth?.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await chain.proceedAsync(request: request)
    }
}
