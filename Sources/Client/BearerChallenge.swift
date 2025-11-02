import Foundation

struct BearerChallenge {
    let scheme: String
    let parameters: [String: String]

    var error: String? { parameters["error"] }
    var errorDescription: String? { parameters["error_description"] }
    var errorURI: String? { parameters["error_uri"] }

    func value(for key: String) -> String? {
        parameters[key]
    }
}

func parseWWWAuthenticate(_ header: String?) -> BearerChallenge? {
    guard let header, !header.isEmpty else { return nil }

    let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard let firstSpaceIndex = trimmed.firstIndex(of: " ") else {
        // Scheme only (e.g., "Bearer"); treat as challenge with no parameters when the header is a single token
        return trimmed.contains("=") ? nil : BearerChallenge(scheme: trimmed, parameters: [:])
    }

    let scheme = String(trimmed[..<firstSpaceIndex]).trimmingCharacters(in: .whitespaces)
    guard !scheme.isEmpty else { return nil }

    let parameterString = trimmed[firstSpaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !parameterString.isEmpty else {
        return BearerChallenge(scheme: scheme, parameters: [:])
    }

    let pairs = parameterString.split(separator: ",")

    var parameters: [String: String] = [:]
    parameters.reserveCapacity(pairs.count)

    for rawPair in pairs {
        let pair = rawPair.trimmingCharacters(in: .whitespaces)
        guard !pair.isEmpty else { continue }

        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
            return nil
        }

        let key = parts[0].trimmingCharacters(in: .whitespaces)
        var value = parts[1].trimmingCharacters(in: .whitespaces)

        guard !key.isEmpty else { return nil }

        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }

        parameters[key.lowercased()] = value
    }

    return BearerChallenge(scheme: scheme, parameters: parameters)
}

