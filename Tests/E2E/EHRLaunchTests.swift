import XCTest

@testable import SMART

@MainActor
final class EHRLaunchTests: XCTestCase {

    func testEHRLaunchHappyPathCreatesContextAndReadsPatient() async throws {
        let prepared = try await SharedLaunchTestHelper.prepareStandaloneClient(testCase: self)
        let client = prepared.client
        let artifacts = prepared.artifacts
        let callbackListener = prepared.callback
        defer { artifacts.emitAttachments() }

        let contextCreation = try await EHRLaunchTestHelper.createLaunchContext(testCase: self)
        try await client.handleEHRLaunch(
            iss: contextCreation.environment.issuer.absoluteString,
            launch: contextCreation.contextId
        )

        let outcome = await SharedLaunchTestHelper.executeAuthorization(
            client: client,
            callbackListener: callbackListener,
            artifacts: artifacts
        )

        XCTAssertNil(
            outcome.redirectError,
            "Redirect handling failed: \(String(describing: outcome.redirectError))")
        XCTAssertNil(
            outcome.authorizeError,
            "Authorization failed: \(String(describing: outcome.authorizeError))")

        if artifacts.authorizeURL == nil,
            let captured = await ExternalLoginDriver.takeRecordedAuthorizeURL()
        {
            artifacts.recordAuthorizeURL(captured)
        }
        if artifacts.authorizeURL == nil,
            let reconstructed = await SharedLaunchTestHelper.reconstructAuthorizeURL(from: client)
        {
            artifacts.recordAuthorizeURL(reconstructed)
        }

        guard let authorizeURL = artifacts.authorizeURL,
            let authorizeComponents = URLComponents(
                url: authorizeURL, resolvingAgainstBaseURL: false)
        else {
            XCTFail("Authorize URL was not captured")
            return
        }

        let launchParam = authorizeComponents.queryItems?.first(where: { $0.name == "launch" })?
            .value
        XCTAssertEqual(
            launchParam,
            contextCreation.contextId,
            "Authorize request must include launch parameter"
        )

        guard let patient = outcome.patient else {
            XCTFail("Expected patient resource after authorization")
            return
        }

        guard let launchPatient = client.server.launchContext?.patient else {
            XCTFail("Expected launch context patient identifier")
            return
        }
        XCTAssertEqual(
            launchPatient,
            contextCreation.patientReference,
            "Launch context should match stored patient reference"
        )

        let normalizedPatientId: String
        if let expectedId = launchPatient.split(separator: "/").last {
            normalizedPatientId = String(expectedId)
            XCTAssertEqual(patient.id?.value?.string, normalizedPatientId)
        } else {
            normalizedPatientId = launchPatient
        }

        let refreshedPatient = try await client.server.readPatient(id: normalizedPatientId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(refreshedPatient) {
            artifacts.recordPatientData(data)
        }
    }
}
