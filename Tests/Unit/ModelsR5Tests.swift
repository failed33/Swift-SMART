import ModelsR5
@testable import SMART
import XCTest

final class ModelsR5Tests: XCTestCase {
    func testFHIRPrimitiveStringConvenience() {
        let primitive = FHIRPrimitive(FHIRString("Hello"))
        XCTAssertEqual(primitive.string, "Hello")

        let optional: FHIRPrimitive<FHIRString>? = nil
        XCTAssertNil(optional.string)
    }

    func testFHIRPrimitiveDateConvenience() throws {
        let date = ISO8601DateFormatter().date(from: "2023-05-01T00:00:00Z")!
        let fhirDate = try FHIRDate(date: date)
        let primitive = FHIRPrimitive(fhirDate)

        let converted = try XCTUnwrap(primitive.nsDate)
        XCTAssertEqual(converted.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.5)

        let optionalPrimitive: FHIRPrimitive<FHIRDate>? = nil
        XCTAssertNil(optionalPrimitive.nsDate)
    }

    func testFHIRPrimitiveUnsignedIntegerConvenience() {
        let primitive = FHIRPrimitive(FHIRUnsignedInteger(42))
        XCTAssertEqual(primitive.int32, 42)

        let optionalPrimitive: FHIRPrimitive<FHIRUnsignedInteger>? = FHIRPrimitive(FHIRUnsignedInteger(99))
        XCTAssertEqual(optionalPrimitive?.int32, 99)
    }

    func testElementExtensionsFiltering() {
        let identifier = Identifier()
        let ext1 = ModelsR5.Extension(url: FHIRPrimitive(FHIRURI("http://example.org/ext1")))
        let ext2 = ModelsR5.Extension(url: FHIRPrimitive(FHIRURI("http://example.org/ext2")))
        let ext3 = ModelsR5.Extension(url: FHIRPrimitive(FHIRURI("http://example.org/ext1")))

        identifier.extension = [ext1, ext2, ext3]

        let filtered: [ModelsR5.Extension] = (identifier as SMART.Element)
            .extensions(forURI: "http://example.org/ext1")
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.url.value?.url.absoluteString == "http://example.org/ext1" })
    }

    func testLocalizedStringBridgesToNSLocalizedString() {
        let key = "FHIR_TEST_KEY"
        XCTAssertEqual(key.fhir_localized, NSLocalizedString(key, comment: ""))
    }
}

