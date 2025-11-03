import HTTPClient
import ModelsR5
import XCTest

@testable import SMART

final class FHIROperationsTests: XCTestCase {
    private func makeServer(using httpClient: MockHTTPClient) -> Server {
        Server(baseURL: URL(string: "https://example.org/fhir/")!, httpClient: httpClient)
    }

    func testDecodingOperationReturnsPatientResource() async throws {
        let httpClient = MockHTTPClient()
        let server = makeServer(using: httpClient)

        let data = try FixtureLoader.data(named: "patient-example")
        let requestURL = URL(string: "https://example.org/fhir/Patient/example")!
        httpClient.setResponse(for: requestURL, data: data)

        let operation = DecodingFHIRRequestOperation<ModelsR5.Patient>(path: "Patient/example")

        let patient = try await server.fhirClient.execute(operation: operation)

        XCTAssertEqual(patient.id?.value?.string, "example")
        XCTAssertEqual(httpClient.requestCount(for: requestURL.path), 1)
    }

    func testRawOperationSendsHeadersAndBody() async throws {
        let httpClient = MockHTTPClient()
        let server = makeServer(using: httpClient)

        let responseData = Data("{}".utf8)
        let requestURL = URL(string: "https://example.org/fhir/Patient")!
        httpClient.setResponse(for: requestURL, data: responseData, statusCode: 201)

        let payload = Data("{\"resourceType\":\"Patient\"}".utf8)
        let operation = RawFHIRRequestOperation(
            path: "Patient",
            method: .post,
            headers: ["Content-Type": "application/fhir+json"],
            body: payload
        )

        let response = try await server.fhirClient.execute(operation: operation)

        XCTAssertEqual(response.status, .created)

        let request = try XCTUnwrap(httpClient.lastRequest())
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/fhir+json")
        XCTAssertEqual(request.httpBody, payload)
    }

    func testFetchPatientMapsHTTPErrorToSMARTClientError() async throws {
        let httpClient = MockHTTPClient()
        let server = makeServer(using: httpClient)

        let data = try FixtureLoader.data(named: "error-401")
        let requestURL = URL(string: "https://example.org/fhir/Patient/example")!
        httpClient.setResponse(for: requestURL, data: data, statusCode: 401)

        do {
            _ = try await server.readPatient(id: "example")
            XCTFail("Expected failure, received success")
        } catch {
            guard let smartError = error as? SMARTClientError else {
                XCTFail("Expected SMARTClientError, received: \(error)")
                return
            }

            guard case .http(let status, let url, _, let outcome, let underlying) = smartError
            else {
                XCTFail("Expected SMARTClientError.http, received: \(smartError)")
                return
            }

            XCTAssertEqual(status, 401)
            XCTAssertTrue(url.absoluteString.hasSuffix("Patient/example"))
            XCTAssertEqual(outcome?.issue.first?.diagnostics?.string, "Access token is invalid")

            if let httpError = underlying as? HTTPClientError,
                case .httpError(let urlError) = httpError
            {
                XCTAssertEqual(urlError.errorCode, 401)
            } else {
                XCTFail("Expected underlying HTTPClientError.httpError")
            }
        }

        XCTAssertEqual(httpClient.requestCount(for: requestURL.path), 1)
    }

    func testReadPatientCancellationPropagatesCancellationError() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responseDelay = 0.5
        let server = makeServer(using: httpClient)

        let data = try FixtureLoader.data(named: "patient-example")
        let requestURL = URL(string: "https://example.org/fhir/Patient/example")!
        httpClient.setResponse(for: requestURL, data: data)

        let task = _Concurrency.Task {
            try await server.readPatient(id: "example")
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected task to throw CancellationError")
        } catch is CancellationError {
            // expected cancellation
        } catch {
            XCTFail("Expected CancellationError, received: \(error)")
        }

        XCTAssertEqual(httpClient.requestCount(for: requestURL.path), 1)
    }
}
