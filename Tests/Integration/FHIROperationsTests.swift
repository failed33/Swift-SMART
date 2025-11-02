@testable import SMART
import Combine
import HTTPClient
import ModelsR5
import XCTest

final class FHIROperationsTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    private func makeServer(using httpClient: MockHTTPClient) -> Server {
        Server(baseURL: URL(string: "https://example.org/fhir/")!, httpClient: httpClient)
    }

    func testDecodingOperationReturnsPatientResource() throws {
        let httpClient = MockHTTPClient()
        let server = makeServer(using: httpClient)

        let data = try FixtureLoader.data(named: "patient-example")
        let requestURL = URL(string: "https://example.org/fhir/Patient/example")!
        httpClient.setResponse(for: requestURL, data: data)

        let expectation = expectation(description: "Decoded patient")

        let operation = DecodingFHIRRequestOperation<ModelsR5.Patient>(path: "Patient/example")

        server.fhirClient.execute(operation: operation)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Expected success, received error: \(error)")
                }
            }, receiveValue: { patient in
                XCTAssertEqual(patient.id?.value?.string, "example")
                expectation.fulfill()
            })
            .store(in: &cancellables)

        waitForExpectations(timeout: 2)
        XCTAssertEqual(httpClient.requestCount(for: requestURL.path), 1)
    }

    func testRawOperationSendsHeadersAndBody() throws {
        let httpClient = MockHTTPClient()
        let server = makeServer(using: httpClient)

        let responseData = Data("{}".utf8)
        let requestURL = URL(string: "https://example.org/fhir/Patient")!
        httpClient.setResponse(for: requestURL, data: responseData, statusCode: 201)

        let expectation = expectation(description: "Raw request completes")

        let payload = Data("{\"resourceType\":\"Patient\"}".utf8)
        let operation = RawFHIRRequestOperation(
            path: "Patient",
            method: .post,
            headers: ["Content-Type": "application/fhir+json"],
            body: payload
        )

        server.fhirClient.execute(operation: operation)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Expected success, received error: \(error)")
                }
            }, receiveValue: { response in
                XCTAssertEqual(response.status, .created)
                expectation.fulfill()
            })
            .store(in: &cancellables)

        waitForExpectations(timeout: 2)

        let request = try XCTUnwrap(httpClient.lastRequest())
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/fhir+json")
        XCTAssertEqual(request.httpBody, payload)
    }

    func testFetchPatientMapsHTTPErrorToSMARTClientError() throws {
        let httpClient = MockHTTPClient()
        let server = makeServer(using: httpClient)

        let data = try FixtureLoader.data(named: "error-401")
        let requestURL = URL(string: "https://example.org/fhir/Patient/example")!
        httpClient.setResponse(for: requestURL, data: data, statusCode: 401)

        let expectation = expectation(description: "Request fails with SMARTClientError.http")

        server.fetchPatient(id: "example") { result in
            switch result {
            case .success:
                XCTFail("Expected failure, received success")
            case .failure(let error):
                guard let smartError = error as? SMARTClientError else {
                    XCTFail("Expected SMARTClientError, received: \(error)")
                    return
                }
                guard case let .http(status, url, _, outcome, underlying) = smartError else {
                    XCTFail("Expected SMARTClientError.http, received: \(smartError)")
                    return
                }
                XCTAssertEqual(status, 401)
                XCTAssertTrue(url.absoluteString.hasSuffix("Patient/example"))
                XCTAssertEqual(outcome?.issue.first?.diagnostics?.string, "Access token is invalid")
                if let httpError = underlying as? HTTPClientError,
                   case let .httpError(urlError) = httpError {
                    XCTAssertEqual(urlError.errorCode, 401)
                } else {
                    XCTFail("Expected underlying HTTPClientError.httpError")
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 2)
        XCTAssertEqual(httpClient.requestCount(for: requestURL.path), 1)
    }
}

