import SMART
import XCTest

final class LaunchContextTests: XCTestCase {
    func testDecodingLaunchContextFixture() throws {
        let context = try FixtureLoader.decode(LaunchContext.self, named: "launch-context")

        XCTAssertEqual(context.patient, "12345")
        XCTAssertEqual(context.encounter, "enc-67890")
        XCTAssertEqual(context.user?.absoluteString, "https://example.org/Practitioner/practitioner-1")
        XCTAssertEqual(context.needPatientBanner, true)
        XCTAssertEqual(context.smartStyleURL?.absoluteString, "https://example.org/style.json")
        XCTAssertEqual(context.intent, "order")
        XCTAssertEqual(context.tenant, "tenant-alpha")
        XCTAssertEqual(context.location, "Location/42")

        let fhirContext = try XCTUnwrap(context.fhirContext)
        XCTAssertEqual(fhirContext.count, 2)

        let medicationContext = try XCTUnwrap(fhirContext.first?.value as? [String: Any])
        XCTAssertEqual(medicationContext["resourceType"] as? String, "MedicationRequest")
        XCTAssertEqual(medicationContext["id"] as? String, "med-1")

        let additionalFlag = context.additionalFields["additional_flag"]?.value as? String
        XCTAssertEqual(additionalFlag, "true")
    }

    func testAdditionalFieldsPersistAfterEncoding() throws {
        let context = try FixtureLoader.decode(LaunchContext.self, named: "launch-context")
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(LaunchContext.self, from: data)

        let additionalFlag = decoded.additionalFields["additional_flag"]?.value as? String
        XCTAssertEqual(additionalFlag, "true")
    }
}

