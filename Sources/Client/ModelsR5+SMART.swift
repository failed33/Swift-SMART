//
//  ModelsR5+SMART.swift
//  Swift-SMART
//
//  Created as part of the Swift-FHIR → ModelsR5 migration.
//

import Foundation
import ModelsR5

// MARK: - FHIRPrimitive Compatibility

extension FHIRPrimitive where PrimitiveType == FHIRString {
    /// Mirrors the Swift-FHIR convenience accessor that returned the underlying `String`.
    public var string: String {
        value?.string ?? ""
    }
}

extension Optional where Wrapped == FHIRPrimitive<FHIRString> {
    /// Convenience accessor returning the underlying optional `String` value.
    public var string: String? {
        switch self {
        case .some(let primitive):
            return primitive.value?.string
        case .none:
            return nil
        }
    }
}

extension FHIRPrimitive where PrimitiveType == FHIRDate {
    /// Provides the historic `.nsDate` convenience computed property.
    public var nsDate: Date? {
        guard let value else { return nil }
        return try? value.asNSDate()
    }
}

extension Optional where Wrapped == FHIRPrimitive<FHIRDate> {
    /// Optional variant of the `.nsDate` convenience property.
    public var nsDate: Date? {
        switch self {
        case .some(let primitive):
            return primitive.nsDate
        case .none:
            return nil
        }
    }
}

extension FHIRPrimitive where PrimitiveType == FHIRUnsignedInteger {
    /// Accessor bridging the old `.int32` helper.
    public var int32: Int32? {
        value?.integer
    }
}

extension Optional where Wrapped == FHIRPrimitive<FHIRUnsignedInteger> {
    /// Optional accessor bridging the old `.int32` helper.
    public var int32: Int32? {
        switch self {
        case .some(let primitive):
            return primitive.int32
        case .none:
            return nil
        }
    }
}

// MARK: - Element Extensions

extension Element {
    /// Mirrors Swift-FHIR's historic `extensions(forURI:)` helper.
    public func extensions(forURI uri: String) -> [ModelsR5.Extension] {
        `extension`?.filter { $0.url.value?.url.absoluteString == uri } ?? []
    }
}

// MARK: - String Localization

extension String {
    /// Convenience getter using `NSLocalizedString()` with no comment.
    public var fhir_localized: String {
        #if os(Linux)
            return self
        #else
            return NSLocalizedString(self, comment: "")
        #endif
    }
}
