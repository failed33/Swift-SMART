import Foundation
import HTTPClient
import OAuth2
import _Concurrency

final class AuthRefreshInterceptor: Interceptor {
    weak var auth: Auth?

    private let coordinator: RefreshCoordinator

    @MainActor
    init(
        auth: Auth?,
        refreshAction: @escaping @Sendable (Auth) async throws -> Void = AuthRefreshInterceptor
            .performRefresh
    ) {
        self.auth = auth
        self.coordinator = RefreshCoordinator { auth in
            try await refreshAction(auth)
        }
    }

    func interceptAsync(chain: Chain) async throws -> HTTPResponse {
        try await process(chain: chain, request: chain.request, hasRetried: false)
    }

    private func process(chain: Chain, request: URLRequest, hasRetried: Bool) async throws
        -> HTTPResponse
    {
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

        guard let token = await MainActor.run(body: { auth.accessToken() }), !token.isEmpty else {
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
            challenge.scheme.caseInsensitiveCompare("Bearer") == .orderedSame
        else {
            return false
        }

        if let error = challenge.error?.lowercased() {
            return error == "invalid_token"
        }

        return false
    }
}

@MainActor
private final class RefreshCoordinator {
    private var currentTask: _Concurrency.Task<Void, Error>?
    private let refreshAction: @Sendable (Auth) async throws -> Void

    init(refreshAction: @escaping @Sendable (Auth) async throws -> Void) {
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
        try await auth.refreshAccessToken()
    }
}

extension AuthRefreshInterceptor: @unchecked Sendable {}
