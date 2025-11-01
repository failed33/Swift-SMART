//
//  LaunchContext.swift
//  Swift-SMART
//
//  Parses SMART App Launch token response context parameters.
//

import Foundation

public struct LaunchContext: Codable, Sendable {
    public let patient: String?
    public let encounter: String?
    public let user: URL?
    public let needPatientBanner: Bool?
    public let smartStyleURL: URL?
    public let intent: String?
    public let tenant: String?
    public let location: String?
    public let fhirContext: [AnyCodable]?
    public let additionalFields: [String: AnyCodable]

    public init(
        patient: String? = nil,
        encounter: String? = nil,
        user: URL? = nil,
        needPatientBanner: Bool? = nil,
        smartStyleURL: URL? = nil,
        intent: String? = nil,
        tenant: String? = nil,
        location: String? = nil,
        fhirContext: [AnyCodable]? = nil,
        additionalFields: [String: AnyCodable] = [:]
    ) {
        self.patient = patient
        self.encounter = encounter
        self.user = user
        self.needPatientBanner = needPatientBanner
        self.smartStyleURL = smartStyleURL
        self.intent = intent
        self.tenant = tenant
        self.location = location
        self.fhirContext = fhirContext
        self.additionalFields = additionalFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case patient
        case encounter
        case user = "fhirUser"
        case needPatientBanner = "need_patient_banner"
        case smartStyleURL = "smart_style_url"
        case intent
        case tenant
        case location
        case fhirContext = "fhirContext"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        patient = try container.decodeIfPresent(String.self, forKey: .patient)
        encounter = try container.decodeIfPresent(String.self, forKey: .encounter)
        user = try container.decodeIfPresent(URL.self, forKey: .user)
        needPatientBanner = try container.decodeIfPresent(Bool.self, forKey: .needPatientBanner)
        smartStyleURL = try container.decodeIfPresent(URL.self, forKey: .smartStyleURL)
        intent = try container.decodeIfPresent(String.self, forKey: .intent)
        tenant = try container.decodeIfPresent(String.self, forKey: .tenant)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        fhirContext = try container.decodeIfPresent([AnyCodable].self, forKey: .fhirContext)

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
        try container.encodeIfPresent(patient, forKey: .patient)
        try container.encodeIfPresent(encounter, forKey: .encounter)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(needPatientBanner, forKey: .needPatientBanner)
        try container.encodeIfPresent(smartStyleURL, forKey: .smartStyleURL)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(tenant, forKey: .tenant)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(fhirContext, forKey: .fhirContext)

        if !additionalFields.isEmpty {
            var remainder = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in additionalFields {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                try remainder.encode(value, forKey: codingKey)
            }
        }
    }
}
