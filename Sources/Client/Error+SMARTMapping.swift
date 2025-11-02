import Foundation
import FHIRClient
import HTTPClient
import ModelsR5
import OAuth2

extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        if let oauthError = self as? OAuth2Error, case .requestCancelled = oauthError { return true }
        if let httpError = self as? HTTPClientError,
           case let .httpError(urlError) = httpError,
           urlError.code == .cancelled {
            return true
        }
        return false
    }
}

enum OperationOutcomeDecoder {
    static func decode(_ data: Data?) -> ModelsR5.OperationOutcome? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ModelsR5.OperationOutcome.self, from: data)
    }
}

enum SMARTErrorMapper {
    static func mapPublic(
        error: Error,
        url: URL?,
        response: HTTPURLResponse? = nil,
        data: Data? = nil
    ) -> SMARTClientError {
        if let smartError = error as? SMARTClientError {
            return smartError
        }

        if error.isCancellation {
            return .cancelled
        }

        if let fhirError = error as? FHIRClient.Error {
            return mapFHIRClientError(fhirError, url: url, response: response, data: data)
        }

        if let httpClientError = error as? HTTPClientError {
            return mapHTTPClientError(httpClientError, url: url, response: response, data: data)
        }

        if let oauthError = error as? OAuth2Error {
            return mapOAuth2Error(oauthError, tokenEndpoint: url)
        }

        if let urlError = error as? URLError {
            return .network(underlying: urlError)
        }

        return .other(underlying: error)
    }

    private static func mapFHIRClientError(
        _ error: FHIRClient.Error,
        url: URL?,
        response: HTTPURLResponse?,
        data: Data?
    ) -> SMARTClientError {
        switch error {
        case .http(let httpError):
            let headers = response?.allHeaderFields as? [String: String] ?? [:]
            let status = response?.statusCode ?? statusCode(from: httpError.httpClientError)
            let finalURL = url ?? response?.url ?? URL(string: "about:blank")!
            return .http(
                status: status,
                url: finalURL,
                headers: headers,
                outcome: httpError.operationOutcome ?? OperationOutcomeDecoder.decode(data),
                underlying: httpError.httpClientError
            )
        case .decoding(let underlying):
            return .decoding(
                url: url ?? response?.url,
                underlying: underlying,
                bodySnippet: data.flatMap(bodySnippet)
            )
        case .internalError(let message):
            let underlying = NSError(
                domain: "FHIRClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            return .other(underlying: underlying)
        case .inconsistentResponse:
            let underlying = NSError(
                domain: "FHIRClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Inconsistent response"]
            )
            return .other(underlying: underlying)
        case .unknown(let underlying):
            return .other(underlying: underlying)
        }
    }

    private static func mapHTTPClientError(
        _ error: HTTPClientError,
        url: URL?,
        response: HTTPURLResponse?,
        data: Data?
    ) -> SMARTClientError {
        let finalURL = url ?? response?.url ?? URL(string: "about:blank")!
        switch error {
        case .httpError(let underlying):
            let headers = response?.allHeaderFields as? [String: String] ?? [:]
            let status = response?.statusCode ?? underlying.errorCode
            return .http(
                status: status,
                url: finalURL,
                headers: headers,
                outcome: OperationOutcomeDecoder.decode(data),
                underlying: underlying
            )
        case .internalError,
             .networkError,
             .authentication,
             .vauError,
             .unknown:
            return .network(underlying: error)
        }
    }

    private static func mapOAuth2Error(_ error: OAuth2Error, tokenEndpoint: URL?) -> SMARTClientError {
        if case .requestCancelled = error {
            return .cancelled
        }
        return .oauth(tokenEndpoint: tokenEndpoint, underlying: error)
    }

    private static func statusCode(from error: HTTPClientError) -> Int {
        if case let .httpError(urlError) = error {
            return urlError.errorCode
        }
        return -1
    }

    private static func bodySnippet(from data: Data) -> String {
        let maxLength = 512
        var snippet = String(decoding: data.prefix(maxLength), as: UTF8.self)
        if data.count > maxLength {
            snippet.append("…")
        }
        return snippet
    }
}

