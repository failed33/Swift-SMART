import Combine
import Foundation
import HTTPClient
import OAuth2
import _Concurrency

final class AuthRefreshInterceptor: Interceptor {
    weak var auth: Auth?

    private let coordinator: RefreshCoordinator

    init(
        auth: Auth?,
        refreshAction: @escaping (Auth) async throws -> Void = AuthRefreshInterceptor.performRefresh
    ) {
        self.auth = auth
        self.coordinator = RefreshCoordinator(refreshAction: refreshAction)
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
        try await process(chain: chain, request: chain.request, hasRetried: false)
    }

    private func process(chain: Chain, request: URLRequest, hasRetried: Bool) async throws -> HTTPResponse {
        let response = try await chain.proceedAsync(request: request)

        guard shouldAttemptRefresh(response: response, hasRetried: hasRetried) else {
            return response
        }

        guard let auth else {
            return response
        }

        do {
            try await coordinator.refresh(using: auth)
        } catch {
            throw HTTPClientError.authentication(error)
        }

        guard let token = auth.oauth?.accessToken, !token.isEmpty else {
            throw HTTPClientError.authentication(OAuth2Error.noAccessToken)
        }

        var retriedRequest = request
        retriedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await process(chain: chain, request: retriedRequest, hasRetried: true)
    }

    private func shouldAttemptRefresh(response: HTTPResponse, hasRetried: Bool) -> Bool {
        guard !hasRetried,
              response.status == .unauthorized,
              let header = response.response.value(forHTTPHeaderField: "WWW-Authenticate"),
              let challenge = parseWWWAuthenticate(header),
              challenge.scheme.caseInsensitiveCompare("Bearer") == .orderedSame else {
            return false
        }

        if let error = challenge.error?.lowercased() {
            return error == "invalid_token"
        }

        return false
    }
}

private actor RefreshCoordinator {
    private var currentTask: _Concurrency.Task<Void, Error>?
    private let refreshAction: (Auth) async throws -> Void

    init(refreshAction: @escaping (Auth) async throws -> Void) {
        self.refreshAction = refreshAction
    }

    func refresh(using auth: Auth) async throws {
        if let task = currentTask {
            return try await task.value
        }

        let task = _Concurrency.Task {
            try await refreshAction(auth)
        }

        currentTask = task
        defer { currentTask = nil }

        try await task.value
    }
}

extension AuthRefreshInterceptor {
    private static func performRefresh(auth: Auth) async throws {
        guard let oauth = auth.oauth else {
            throw OAuth2Error.noAccessToken
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            oauth.tryToObtainAccessTokenIfNeeded { params, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if params != nil || oauth.hasUnexpiredAccessToken() {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: OAuth2Error.noRefreshToken)
                }
            }
        }
    }
}

