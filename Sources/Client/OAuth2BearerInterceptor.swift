//
//  OAuth2BearerInterceptor.swift
//  Swift-SMART
//
//  Injects the OAuth2 access token into outgoing HTTP requests.
//

import Foundation
import HTTPClient

final class OAuth2BearerInterceptor: Interceptor {
    weak var auth: Auth?

    init(auth: Auth?) {
        self.auth = auth
    }

    func interceptAsync(chain: Chain) async throws -> HTTPResponse {
        var request = chain.request

        if let auth,
            let token = await MainActor.run(body: { auth.accessToken() }),
            !token.isEmpty
        {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await chain.proceedAsync(request: request)
    }
}
