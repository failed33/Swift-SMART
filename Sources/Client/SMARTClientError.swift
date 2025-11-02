import Foundation
import ModelsR5

public enum SMARTClientError: Error {
    case configuration(url: URL, underlying: Error)
    case oauth(tokenEndpoint: URL?, underlying: Error)
    case http(status: Int, url: URL, headers: [String: String],
              outcome: ModelsR5.OperationOutcome?, underlying: Error)
    case decoding(url: URL?, underlying: Error, bodySnippet: String?)
    case cancelled
    case rateLimited(retryAfter: Date?, url: URL)
    case network(underlying: Error)
    case other(underlying: Error)
}

extension SMARTClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configuration(let url, let underlying):
            return "Configuration error for \(url.absoluteString): \(underlying.localizedDescription)"
        case .oauth(_, let underlying):
            return underlying.localizedDescription
        case .http(let status, let url, _, let outcome, let underlying):
            if let issue = outcome?.issue.first,
               let issueText = issue.diagnostics?.string ?? issue.details?.text?.value?.string {
                return "HTTP \(status) for \(url.absoluteString): \(issueText)"
            }
            return "HTTP \(status) for \(url.absoluteString): \(underlying.localizedDescription)"
        case .decoding(let url, _, _):
            if let url {
                return "Failed to decode response for \(url.absoluteString)"
            }
            return "Failed to decode response"
        case .cancelled:
            return "Operation was cancelled"
        case .rateLimited(let retryAfter, let url):
            if let retryAfter {
                return "Rate limited for \(url.absoluteString). Retry after \(retryAfter)"
            }
            return "Rate limited for \(url.absoluteString)"
        case .network(let underlying), .other(let underlying):
            return underlying.localizedDescription
        }
    }
}

extension SMARTClientError: CustomNSError {
    public static var errorDomain: String { "SMARTClientError" }

    public var errorCode: Int {
        switch self {
        case .configuration:
            return 1
        case .oauth:
            return 2
        case .http:
            return 3
        case .decoding:
            return 4
        case .cancelled:
            return 5
        case .rateLimited:
            return 6
        case .network:
            return 7
        case .other:
            return 8
        }
    }

    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]

        switch self {
        case .configuration(let url, let underlying):
            userInfo[NSURLErrorKey] = url
            userInfo[NSUnderlyingErrorKey] = underlying
        case .oauth(let tokenEndpoint, let underlying):
            if let tokenEndpoint {
                userInfo[NSURLErrorKey] = tokenEndpoint
            }
            userInfo[NSUnderlyingErrorKey] = underlying
        case .http(_, let url, let headers, let outcome, let underlying):
            userInfo[NSURLErrorKey] = url
            userInfo["HTTPHeaders"] = headers
            if let outcome,
               let outcomeData = try? JSONEncoder().encode(outcome) {
                userInfo["OperationOutcome"] = outcomeData
            }
            userInfo[NSUnderlyingErrorKey] = underlying
        case .decoding(let url, let underlying, let bodySnippet):
            if let url {
                userInfo[NSURLErrorKey] = url
            }
            if let bodySnippet {
                userInfo["BodySnippet"] = bodySnippet
            }
            userInfo[NSUnderlyingErrorKey] = underlying
        case .cancelled:
            break
        case .rateLimited(let retryAfter, let url):
            userInfo[NSURLErrorKey] = url
            if let retryAfter {
                userInfo["RetryAfter"] = retryAfter
            }
        case .network(let underlying), .other(let underlying):
            userInfo[NSUnderlyingErrorKey] = underlying
        }

        return userInfo
    }
}

