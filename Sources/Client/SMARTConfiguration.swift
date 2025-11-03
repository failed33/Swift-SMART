//
//  SMARTConfiguration.swift
//  Swift-SMART
//
//  Representation of `.well-known/smart-configuration` discovery data.
//

import Foundation

public struct SMARTConfiguration: Codable, Sendable {
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let registrationEndpoint: URL?
    public let managementEndpoint: URL?
    public let introspectionEndpoint: URL?
    public let revocationEndpoint: URL?
    public let jwksEndpoint: URL?
    public let issuer: URL?

    public let grantTypesSupported: [String]?
    public let responseTypesSupported: [String]?
    public let scopesSupported: [String]?
    public let codeChallengeMethodsSupported: [String]?
    public let tokenEndpointAuthMethodsSupported: [String]?
    public let tokenEndpointAuthSigningAlgValuesSupported: [String]?
    public let capabilities: [String]?
    public let smartVersion: String?
    public let fhirVersion: String?

    /// Some servers supply additional fields. Preserve them to avoid data-loss.
    public let additionalFields: [String: AnyCodable]

    public init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        registrationEndpoint: URL? = nil,
        managementEndpoint: URL? = nil,
        introspectionEndpoint: URL? = nil,
        revocationEndpoint: URL? = nil,
        jwksEndpoint: URL? = nil,
        issuer: URL? = nil,
        grantTypesSupported: [String]? = nil,
        responseTypesSupported: [String]? = nil,
        scopesSupported: [String]? = nil,
        codeChallengeMethodsSupported: [String]? = nil,
        tokenEndpointAuthMethodsSupported: [String]? = nil,
        tokenEndpointAuthSigningAlgValuesSupported: [String]? = nil,
        capabilities: [String]? = nil,
        smartVersion: String? = nil,
        fhirVersion: String? = nil,
        additionalFields: [String: AnyCodable] = [:]
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.managementEndpoint = managementEndpoint
        self.introspectionEndpoint = introspectionEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.jwksEndpoint = jwksEndpoint
        self.issuer = issuer
        self.grantTypesSupported = grantTypesSupported
        self.responseTypesSupported = responseTypesSupported
        self.scopesSupported = scopesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
        self.tokenEndpointAuthSigningAlgValuesSupported = tokenEndpointAuthSigningAlgValuesSupported
        self.capabilities = capabilities
        self.smartVersion = smartVersion
        self.fhirVersion = fhirVersion
        self.additionalFields = additionalFields
    }

    public static func wellKnownURL(for baseURL: URL) -> URL {
        baseURL.appendingPathComponent(".well-known/smart-configuration")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case managementEndpoint = "management_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case jwksEndpoint = "jwks_uri"
        case issuer
        case grantTypesSupported = "grant_types_supported"
        case responseTypesSupported = "response_types_supported"
        case scopesSupported = "scopes_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case tokenEndpointAuthSigningAlgValuesSupported =
            "token_endpoint_auth_signing_alg_values_supported"
        case capabilities
        case smartVersion = "smart_version"
        case fhirVersion = "fhir_version"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        authorizationEndpoint = try container.decode(URL.self, forKey: .authorizationEndpoint)
        tokenEndpoint = try container.decode(URL.self, forKey: .tokenEndpoint)
        registrationEndpoint = try container.decodeIfPresent(
            URL.self, forKey: .registrationEndpoint)
        managementEndpoint = try container.decodeIfPresent(URL.self, forKey: .managementEndpoint)
        introspectionEndpoint = try container.decodeIfPresent(
            URL.self, forKey: .introspectionEndpoint)
        revocationEndpoint = try container.decodeIfPresent(URL.self, forKey: .revocationEndpoint)
        jwksEndpoint = try container.decodeIfPresent(URL.self, forKey: .jwksEndpoint)
        issuer = try container.decodeIfPresent(URL.self, forKey: .issuer)
        grantTypesSupported = try container.decodeIfPresent(
            [String].self, forKey: .grantTypesSupported)
        responseTypesSupported = try container.decodeIfPresent(
            [String].self, forKey: .responseTypesSupported)
        scopesSupported = try container.decodeIfPresent([String].self, forKey: .scopesSupported)
        codeChallengeMethodsSupported = try container.decodeIfPresent(
            [String].self, forKey: .codeChallengeMethodsSupported)
        tokenEndpointAuthMethodsSupported = try container.decodeIfPresent(
            [String].self, forKey: .tokenEndpointAuthMethodsSupported)
        tokenEndpointAuthSigningAlgValuesSupported = try container.decodeIfPresent(
            [String].self, forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities)
        smartVersion = try container.decodeIfPresent(String.self, forKey: .smartVersion)
        fhirVersion = try container.decodeIfPresent(String.self, forKey: .fhirVersion)

        let knownKeys = Set(CodingKeys.allCases.map { $0.rawValue })
        let rawContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var remainder: [String: AnyCodable] = [:]
        for key in rawContainer.allKeys where !knownKeys.contains(key.stringValue) {
            remainder[key.stringValue] = try rawContainer.decode(AnyCodable.self, forKey: key)
        }
        additionalFields = remainder
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(authorizationEndpoint, forKey: .authorizationEndpoint)
        try container.encode(tokenEndpoint, forKey: .tokenEndpoint)
        try container.encodeIfPresent(registrationEndpoint, forKey: .registrationEndpoint)
        try container.encodeIfPresent(managementEndpoint, forKey: .managementEndpoint)
        try container.encodeIfPresent(introspectionEndpoint, forKey: .introspectionEndpoint)
        try container.encodeIfPresent(revocationEndpoint, forKey: .revocationEndpoint)
        try container.encodeIfPresent(jwksEndpoint, forKey: .jwksEndpoint)
        try container.encodeIfPresent(issuer, forKey: .issuer)
        try container.encodeIfPresent(grantTypesSupported, forKey: .grantTypesSupported)
        try container.encodeIfPresent(responseTypesSupported, forKey: .responseTypesSupported)
        try container.encodeIfPresent(scopesSupported, forKey: .scopesSupported)
        try container.encodeIfPresent(
            codeChallengeMethodsSupported, forKey: .codeChallengeMethodsSupported)
        try container.encodeIfPresent(
            tokenEndpointAuthMethodsSupported, forKey: .tokenEndpointAuthMethodsSupported)
        try container.encodeIfPresent(
            tokenEndpointAuthSigningAlgValuesSupported,
            forKey: .tokenEndpointAuthSigningAlgValuesSupported)
        try container.encodeIfPresent(capabilities, forKey: .capabilities)
        try container.encodeIfPresent(smartVersion, forKey: .smartVersion)
        try container.encodeIfPresent(fhirVersion, forKey: .fhirVersion)

        if !additionalFields.isEmpty {
            var remainder = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in additionalFields {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                try remainder.encode(value, forKey: codingKey)
            }
        }
    }
}

// MARK: - Helpers

public enum SMARTConfigurationError: Error, LocalizedError {
    case invalidResponse
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "SMART configuration response was invalid"
        case .invalidHTTPStatus(let status):
            return "SMART configuration request failed with status \(status)"
        }
    }
}

public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            let encodableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(encodableArray)
        case let dictionaryValue as [String: Any]:
            let encodableDictionary = Dictionary(
                uniqueKeysWithValues: dictionaryValue.map { ($0.key, AnyCodable($0.value)) })
            try container.encode(encodableDictionary)
        default:
            try container.encodeNil()
        }
    }
}

public struct DynamicCodingKey: CodingKey {
    public let stringValue: String
    public let intValue: Int?

    public init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
}
