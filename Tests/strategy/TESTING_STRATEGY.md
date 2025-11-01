# Swift-SMART Testing Strategy

## Overview

Comprehensive testing strategy for Swift-SMART library covering unit tests, integration tests, and end-to-end validation against real SMART servers.

---

## Testing Pyramid

```
                    E2E Tests (Real Servers)
                   /                        \
              Integration Tests (Mock HTTP)
             /                                \
        Unit Tests (Pure Logic, No Network)
```

---

## Testing Scope & Exclusions

### Components EXCLUDED from Testing

**`Sources/helpers/` directory** - Presentation/UI helpers excluded per project requirements:

- `PatientList.swift` - Patient list UI management
- `PatientListQuery.swift` - Query building helpers
- `PatientListOrder.swift` - Patient sorting and display formatting
- `iOS/Auth+iOS.swift` - iOS-specific UI auth helpers
- `iOS/PatientList+iOS.swift` - iOS-specific patient list UI
- `macOS/Auth+macOS.swift` - macOS-specific UI auth helpers

These components are considered presentation layer helpers and will be validated through integration and manual testing rather than unit tests.

---

## 1. Unit Tests (No Network)

Test pure logic components in isolation using mocks and test fixtures.

### 1.1 PKCE Generation

**File:** `Tests/PKCETests.swift`

```swift
import XCTest
@testable import SMART

class PKCETests: XCTestCase {

    func testPKCEGeneration() {
        let pkce = PKCE.generate()

        // Verifier should be 64 characters by default
        XCTAssertEqual(pkce.codeVerifier.count, 64)

        // Challenge should be non-empty base64url
        XCTAssertFalse(pkce.codeChallenge.isEmpty)
        XCTAssertFalse(pkce.codeChallenge.contains("+"))
        XCTAssertFalse(pkce.codeChallenge.contains("/"))
        XCTAssertFalse(pkce.codeChallenge.contains("="))

        // Method should be S256
        XCTAssertEqual(pkce.method, "S256")
    }

    func testPKCECustomLength() {
        let pkce43 = PKCE.generate(length: 43)
        XCTAssertEqual(pkce43.codeVerifier.count, 43)

        let pkce128 = PKCE.generate(length: 128)
        XCTAssertEqual(pkce128.codeVerifier.count, 128)

        // Out of bounds should clamp
        let pkceTooShort = PKCE.generate(length: 10)
        XCTAssertEqual(pkceTooShort.codeVerifier.count, 43)

        let pkceTooLong = PKCE.generate(length: 200)
        XCTAssertEqual(pkceTooLong.codeVerifier.count, 128)
    }

    func testPKCEVerifierCharacterSet() {
        let pkce = PKCE.generate()
        let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

        for char in pkce.codeVerifier.unicodeScalars {
            XCTAssertTrue(allowedChars.contains(char))
        }
    }

    // ✅ Known test vector from RFC 7636 Appendix B
    func testPKCEChallengeDerivation() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let challenge = PKCE.deriveCodeChallenge(from: verifier)
        XCTAssertEqual(challenge, expectedChallenge)
    }

    func testPKCEUniqueness() {
        let pkce1 = PKCE.generate()
        let pkce2 = PKCE.generate()

        XCTAssertNotEqual(pkce1.codeVerifier, pkce2.codeVerifier)
        XCTAssertNotEqual(pkce1.codeChallenge, pkce2.codeChallenge)
    }
}
```

---

### 1.2 SMART Configuration Parsing

**File:** `Tests/SMARTConfigurationTests.swift`

```swift
import XCTest
@testable import SMART

class SMARTConfigurationTests: XCTestCase {

    func testMinimalConfiguration() throws {
        let json = """
        {
            "authorization_endpoint": "https://auth.example.org/authorize",
            "token_endpoint": "https://auth.example.org/token"
        }
        """

        let config = try JSONDecoder().decode(SMARTConfiguration.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(config.authorizationEndpoint.absoluteString, "https://auth.example.org/authorize")
        XCTAssertEqual(config.tokenEndpoint.absoluteString, "https://auth.example.org/token")
        XCTAssertNil(config.capabilities)
        XCTAssertNil(config.scopesSupported)
    }

    func testFullConfiguration() throws {
        let json = """
        {
            "authorization_endpoint": "https://ehr.example.org/auth/authorize",
            "token_endpoint": "https://ehr.example.org/auth/token",
            "registration_endpoint": "https://ehr.example.org/auth/register",
            "capabilities": ["launch-ehr", "permission-patient", "client-public"],
            "scopes_supported": ["patient/*.rs", "openid", "fhirUser"],
            "code_challenge_methods_supported": ["S256"],
            "grant_types_supported": ["authorization_code"],
            "response_types_supported": ["code"]
        }
        """

        let config = try JSONDecoder().decode(SMARTConfiguration.self, from: json.data(using: .utf8)!)

        XCTAssertNotNil(config.registrationEndpoint)
        XCTAssertEqual(config.capabilities?.count, 3)
        XCTAssertTrue(config.capabilities!.contains("launch-ehr"))
        XCTAssertEqual(config.codeChallengeMethodsSupported, ["S256"])
    }

    func testConfigurationWithAdditionalFields() throws {
        let json = """
        {
            "authorization_endpoint": "https://ehr.example.org/authorize",
            "token_endpoint": "https://ehr.example.org/token",
            "custom_field": "custom_value",
            "vendor_extension": {"nested": "data"}
        }
        """

        let config = try JSONDecoder().decode(SMARTConfiguration.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(config.additionalFields.count, 2)
        XCTAssertNotNil(config.additionalFields["custom_field"])
    }

    func testWellKnownURL() {
        let baseURL = URL(string: "https://fhir.example.org/fhir")!
        let wellKnown = SMARTConfiguration.wellKnownURL(for: baseURL)

        XCTAssertEqual(wellKnown.absoluteString, "https://fhir.example.org/fhir/.well-known/smart-configuration")
    }
}
```

---

### 1.3 Launch Context Parsing

**File:** `Tests/LaunchContextTests.swift`

```swift
import XCTest
@testable import SMART

class LaunchContextTests: XCTestCase {

    func testMinimalContext() throws {
        let json = """
        {
            "patient": "123"
        }
        """

        let context = try JSONDecoder().decode(LaunchContext.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(context.patient, "123")
        XCTAssertNil(context.encounter)
        XCTAssertNil(context.user)
    }

    func testFullContext() throws {
        let json = """
        {
            "patient": "patient-123",
            "encounter": "encounter-456",
            "fhirUser": "https://ehr.example.org/fhir/Practitioner/789",
            "need_patient_banner": true,
            "smart_style_url": "https://ehr.example.org/style.json",
            "intent": "reconcile-medications",
            "tenant": "org-abc",
            "location": "ward-5",
            "fhirContext": [
                {"reference": "DiagnosticReport/report-1"},
                {"canonical": "http://example.org/Questionnaire/123"}
            ]
        }
        """

        let context = try JSONDecoder().decode(LaunchContext.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(context.patient, "patient-123")
        XCTAssertEqual(context.encounter, "encounter-456")
        XCTAssertEqual(context.user?.absoluteString, "https://ehr.example.org/fhir/Practitioner/789")
        XCTAssertEqual(context.needPatientBanner, true)
        XCTAssertEqual(context.intent, "reconcile-medications")
        XCTAssertEqual(context.tenant, "org-abc")
        XCTAssertEqual(context.fhirContext?.count, 2)
    }

    func testContextWithAdditionalFields() throws {
        let json = """
        {
            "patient": "123",
            "custom_extension": "custom_value"
        }
        """

        let context = try JSONDecoder().decode(LaunchContext.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(context.patient, "123")
        XCTAssertNotNil(context.additionalFields["custom_extension"])
    }
}
```

---

### 1.4 Scope Normalization

**File:** `Tests/AuthTests.swift`

```swift
import XCTest
@testable import SMART

class AuthTests: XCTestCase {

    func testScopeNormalizationV1ToV2() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        // Mock updatedScope method test
        let properties = SMARTAuthProperties()

        // Test v1 -> v2 conversion
        let normalized = auth.updatedScope(from: "patient/*.read", properties: properties)
        XCTAssertTrue(normalized.contains("patient/*.rs"))
        XCTAssertFalse(normalized.contains(".read"))
    }

    func testScopeAddsLaunchContext() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        var properties = SMARTAuthProperties()
        properties.granularity = .launchContext

        let scopes = auth.updatedScope(from: "patient/*.rs", properties: properties)
        XCTAssertTrue(scopes.contains("launch"))
    }

    func testScopeAddsLaunchPatient() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        var properties = SMARTAuthProperties()
        properties.granularity = .patientSelectWeb

        let scopes = auth.updatedScope(from: "patient/*.rs", properties: properties)
        XCTAssertTrue(scopes.contains("launch/patient"))
    }

    func testScopeAlwaysAddsOpenIDAndFHIRUser() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        let properties = SMARTAuthProperties()
        let scopes = auth.updatedScope(from: nil, properties: properties)

        // ✅ SMART v2 requirement: openid + fhirUser always required
        XCTAssertTrue(scopes.contains("openid"))
        XCTAssertTrue(scopes.contains("fhirUser"))
        // Note: profile is OPTIONAL, not required
    }
}
```

---

### 1.5 ModelsR5 Extensions

**File:** `Tests/ModelsR5ExtensionTests.swift`

```swift
import XCTest
import ModelsR5
@testable import SMART

class ModelsR5ExtensionTests: XCTestCase {

    func testFHIRStringConvenience() {
        let primitive = FHIRPrimitive(FHIRString("Hello"))
        XCTAssertEqual(primitive.string, "Hello")

        let nilPrimitive: FHIRPrimitive<FHIRString>? = nil
        XCTAssertNil(nilPrimitive.string)
    }

    func testFHIRDateConvenience() throws {
        let date = Date()
        let fhirDate = try FHIRDate(date: date)
        let primitive = FHIRPrimitive(fhirDate)

        XCTAssertNotNil(primitive.nsDate)

        let calendar = Calendar.current
        let components1 = calendar.dateComponents([.year, .month, .day], from: date)
        let components2 = calendar.dateComponents([.year, .month, .day], from: primitive.nsDate!)

        XCTAssertEqual(components1.year, components2.year)
        XCTAssertEqual(components1.month, components2.month)
        XCTAssertEqual(components1.day, components2.day)
    }

    func testElementExtensionsFilter() {
        let ext1 = ModelsR5.Extension(url: FHIRPrimitive(FHIRURI("http://example.org/ext1")))
        let ext2 = ModelsR5.Extension(url: FHIRPrimitive(FHIRURI("http://example.org/ext2")))
        let ext3 = ModelsR5.Extension(url: FHIRPrimitive(FHIRURI("http://example.org/ext1")))

        let element = DomainResource()
        element.extension = [ext1, ext2, ext3]

        let filtered = element.extensions(for: "http://example.org/ext1")
        XCTAssertEqual(filtered.count, 2)
    }

    func testStringLocalization() {
        let localized = "Test String".fhir_localized
        XCTAssertEqual(localized, NSLocalizedString("Test String", comment: ""))
    }

    func testPatientDisplayName() {
        let patient = ModelsR5.Patient()

        let humanName = HumanName()
        humanName.family = FHIRPrimitive(FHIRString("Smith"))
        humanName.given = [FHIRPrimitive(FHIRString("John"))]
        patient.name = [humanName]

        XCTAssertEqual(patient.displayNameFamilyGiven, "Smith, John")
    }

    func testPatientAge() throws {
        let patient = ModelsR5.Patient()

        let birthDate = Calendar.current.date(byAdding: .year, value: -42, to: Date())!
        patient.birthDate = FHIRPrimitive(try FHIRDate(date: birthDate))

        let age = patient.currentAge
        XCTAssertTrue(age.contains("42"))
    }
}
```

---

## 2. Integration Tests (Mock HTTP)

Test interactions with mocked HTTP responses, no real network calls.

### 2.1 Mock HTTPClient

**File:** `Tests/Mocks/MockHTTPClient.swift`

```swift
import Combine
import Foundation
import HTTPClient

class MockHTTPClient: HTTPClient {
    var interceptors: [Interceptor] = []

    // Record requests for verification
    var recordedRequests: [URLRequest] = []

    // Configure mock responses
    var mockResponses: [String: (Data, Int)] = [:]  // URL path -> (data, statusCode)

    func sendPublisher(request: URLRequest, interceptors: [Interceptor], redirect handler: RedirectHandler?) -> AnyPublisher<HTTPResponse, HTTPClientError> {
        recordedRequests.append(request)

        let path = request.url?.path ?? ""

        guard let (data, statusCode) = mockResponses[path] else {
            return Fail(error: .networkError("Mock not configured for \(path)"))
                .eraseToAnyPublisher()
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        let status = HTTPStatusCode(rawValue: statusCode) ?? .ok
        let response: HTTPResponse = (data, httpResponse, status)

        return Just(response)
            .setFailureType(to: HTTPClientError.self)
            .eraseToAnyPublisher()
    }

    func sendAsync(request: URLRequest, interceptors: [Interceptor], redirect handler: RedirectHandler?) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = sendPublisher(request: request, interceptors: interceptors, redirect: handler)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { response in
                        continuation.resume(returning: response)
                    }
                )
            _ = cancellable  // Keep alive
        }
    }
}
```

---

### 2.2 Server Discovery Tests

**File:** `Tests/Integration/ServerDiscoveryTests.swift`

```swift
import XCTest
import Combine
@testable import SMART

class ServerDiscoveryTests: XCTestCase {

    var cancellables = Set<AnyCancellable>()

    func testSMARTConfigurationFetch() {
        let mockHTTP = MockHTTPClient()
        mockHTTP.mockResponses["/.well-known/smart-configuration"] = (
            """
            {
                "authorization_endpoint": "https://ehr.example.org/authorize",
                "token_endpoint": "https://ehr.example.org/token",
                "capabilities": ["launch-ehr", "client-public"]
            }
            """.data(using: .utf8)!,
            200
        )

        let server = Server(
            baseURL: URL(string: "https://ehr.example.org")!,
            httpClient: mockHTTP
        )

        let expectation = self.expectation(description: "Discovery completes")

        server.getSMARTConfiguration { result in
            switch result {
            case .success(let config):
                XCTAssertEqual(config.authorizationEndpoint.absoluteString, "https://ehr.example.org/authorize")
                XCTAssertEqual(config.capabilities?.count, 2)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Discovery failed: \(error)")
            }
        }

        waitForExpectations(timeout: 5)
    }

    func testSMARTConfigurationCaching() {
        let mockHTTP = MockHTTPClient()
        mockHTTP.mockResponses["/.well-known/smart-configuration"] = (
            """
            {
                "authorization_endpoint": "https://ehr.example.org/authorize",
                "token_endpoint": "https://ehr.example.org/token"
            }
            """.data(using: .utf8)!,
            200
        )

        let server = Server(
            baseURL: URL(string: "https://ehr.example.org")!,
            httpClient: mockHTTP
        )

        let exp1 = expectation(description: "First fetch")
        server.getSMARTConfiguration { _ in exp1.fulfill() }
        waitForExpectations(timeout: 5)

        let requestCount1 = mockHTTP.recordedRequests.count

        let exp2 = expectation(description: "Second fetch (should be cached)")
        server.getSMARTConfiguration { _ in exp2.fulfill() }
        waitForExpectations(timeout: 5)

        // Should not make another HTTP request
        XCTAssertEqual(mockHTTP.recordedRequests.count, requestCount1)
    }
}
```

---

### 2.3 OAuth Interceptor Tests

**File:** `Tests/Integration/OAuth2InterceptorTests.swift`

```swift
import XCTest
import HTTPClient
@testable import SMART

class OAuth2InterceptorTests: XCTestCase {

    func testInterceptorAddsAuthorizationHeader() async throws {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: ["client_id": "test"])

        // Simulate having an access token
        auth.oauth = OAuth2CodeGrant(settings: ["client_id": "test"])
        auth.oauth?.clientConfig.accessToken = "test-token-123"

        let interceptor = OAuth2BearerInterceptor(auth: auth)

        let mockChain = MockChain(request: URLRequest(url: URL(string: "https://fhir.example.org/Patient")!))

        let response = try await interceptor.interceptAsync(chain: mockChain)

        XCTAssertEqual(mockChain.modifiedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-123")
    }

    func testInterceptorWithoutToken() async throws {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .none, server: server, settings: nil)

        let interceptor = OAuth2BearerInterceptor(auth: auth)

        let mockChain = MockChain(request: URLRequest(url: URL(string: "https://fhir.example.org/Patient")!))

        let response = try await interceptor.interceptAsync(chain: mockChain)

        XCTAssertNil(mockChain.modifiedRequest?.value(forHTTPHeaderField: "Authorization"))
    }
}

// Mock chain for testing
class MockChain: Chain {
    var request: URLRequest
    var modifiedRequest: URLRequest?

    init(request: URLRequest) {
        self.request = request
    }

    func proceedPublisher(request: URLRequest) -> AnyPublisher<HTTPResponse, HTTPClientError> {
        modifiedRequest = request
        let data = Data()
        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let response: HTTPResponse = (data, httpResponse, .ok)
        return Just(response).setFailureType(to: HTTPClientError.self).eraseToAnyPublisher()
    }

    func proceedAsync(request: URLRequest) async throws -> HTTPResponse {
        modifiedRequest = request
        let data = Data()
        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, httpResponse, .ok)
    }
}
```

---

### 2.4 FHIR Client Operations Tests

**File:** `Tests/Integration/FHIROperationsTests.swift`

```swift
import XCTest
import Combine
import ModelsR5
@testable import SMART

class FHIROperationsTests: XCTestCase {

    var cancellables = Set<AnyCancellable>()

    func testRawFHIROperation() {
        let mockHTTP = MockHTTPClient()
        mockHTTP.mockResponses["/Patient/123"] = (
            """
            {
                "resourceType": "Patient",
                "id": "123",
                "name": [{"family": "Smith"}]
            }
            """.data(using: .utf8)!,
            200
        )

        let server = Server(
            baseURL: URL(string: "https://fhir.example.org")!,
            httpClient: mockHTTP
        )

        let operation = RawFHIRRequestOperation(
            path: "Patient/123",
            headers: ["Accept": "application/json"]
        )

        let expectation = self.expectation(description: "Operation completes")

        server.fhirClient.execute(operation: operation)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertFalse(response.body.isEmpty)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        waitForExpectations(timeout: 5)
    }

    func testDecodingOperation() {
        let mockHTTP = MockHTTPClient()
        mockHTTP.mockResponses["/Patient/123"] = (
            """
            {
                "resourceType": "Patient",
                "id": "123",
                "name": [{"family": "Smith", "given": ["John"]}]
            }
            """.data(using: .utf8)!,
            200
        )

        let server = Server(
            baseURL: URL(string: "https://fhir.example.org")!,
            httpClient: mockHTTP
        )

        let operation = DecodingFHIRRequestOperation<ModelsR5.Patient>(
            path: "Patient/123",
            headers: ["Accept": "application/fhir+json"]
        )

        let expectation = self.expectation(description: "Operation decodes")

        server.fhirClient.execute(operation: operation)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { patient in
                    XCTAssertEqual(patient.id?.value?.string, "123")
                    XCTAssertEqual(patient.name?.first?.family?.string, "Smith")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        waitForExpectations(timeout: 5)
    }
}
```

---

## 3. End-to-End Tests (Real Servers)

Test against live SMART servers using public sandboxes.

### 3.1 SMART Sandbox Tests

**File:** `Tests/E2E/SMARTSandboxTests.swift`

```swift
import XCTest
import Combine
@testable import SMART

class SMARTSandboxTests: XCTestCase {

    // Use SMART Health IT public sandbox
    let sandboxURL = URL(string: "https://launch.smarthealthit.org/v/r4/fhir")!
    var cancellables = Set<AnyCancellable>()

    func testDiscoveryAgainstRealServer() {
        let server = Server(baseURL: sandboxURL)

        let expectation = self.expectation(description: "Discovery from real server")

        server.getSMARTConfiguration { result in
            switch result {
            case .success(let config):
                XCTAssertNotNil(config.authorizationEndpoint)
                XCTAssertNotNil(config.tokenEndpoint)
                XCTAssertTrue(config.capabilities?.contains("launch-standalone") ?? false)
                XCTAssertTrue(config.codeChallengeMethodsSupported?.contains("S256") ?? false)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Discovery failed: \(error)")
            }
        }

        waitForExpectations(timeout: 10)
    }

    func testPublicResourceAccess() {
        // Some FHIR servers allow unauthenticated read of certain resources
        let server = Server(baseURL: sandboxURL)

        let operation = DecodingFHIRRequestOperation<ModelsR5.CapabilityStatement>(
            path: "metadata",
            headers: ["Accept": "application/fhir+json"]
        )

        let expectation = self.expectation(description: "Metadata fetch")

        server.fhirClient.execute(operation: operation)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Metadata fetch failed: \(error)")
                    }
                },
                receiveValue: { capability in
                    XCTAssertEqual(capability.fhirVersion?.value, .v4_0_1)
                    XCTAssertEqual(capability.kind.value, .instance)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        waitForExpectations(timeout: 10)
    }
}
```

---

### 3.2 OAuth Flow Tests (Manual/UI)

**File:** `Tests/E2E/OAuthFlowTests.swift`

```swift
import XCTest
@testable import SMART

class OAuthFlowManualTests: XCTestCase {

    // These tests require manual interaction and are disabled by default
    // Run with: swift test --filter OAuthFlowManualTests --enable-manual-tests

    func testStandaloneLaunchFlow() {
        // This test opens a browser for user interaction
        #if MANUAL_TESTS
        let client = Client(
            baseURL: URL(string: "https://launch.smarthealthit.org/v/r4/fhir")!,
            settings: [
                "client_id": "test-client-id",
                "redirect": "myapp://callback"
            ]
        )

        let expectation = self.expectation(description: "Authorization completes")

        client.authorize { patient, error in
            XCTAssertNil(error, "Authorization should succeed")
            XCTAssertNotNil(patient, "Should receive patient context")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 120)  // Allow time for user interaction
        #else
        XCTSkip("Manual test disabled; enable with MANUAL_TESTS flag")
        #endif
    }
}
```

---

## 4. Test Fixtures

### 4.1 Mock SMART Configuration

**File:** `Tests/Fixtures/smart-configuration.json`

```json
{
  "issuer": "https://ehr.example.org",
  "authorization_endpoint": "https://ehr.example.org/auth/authorize",
  "token_endpoint": "https://ehr.example.org/auth/token",
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "private_key_jwt"
  ],
  "grant_types_supported": ["authorization_code", "client_credentials"],
  "registration_endpoint": "https://ehr.example.org/auth/register",
  "scopes_supported": [
    "openid",
    "fhirUser",
    "launch",
    "launch/patient",
    "patient/*.rs",
    "user/*.cruds",
    "offline_access"
  ],
  "response_types_supported": ["code"],
  "code_challenge_methods_supported": ["S256"],
  "capabilities": [
    "launch-ehr",
    "launch-standalone",
    "client-public",
    "client-confidential-symmetric",
    "client-confidential-asymmetric",
    "context-ehr-patient",
    "context-ehr-encounter",
    "context-standalone-patient",
    "permission-offline",
    "permission-patient",
    "permission-user",
    "permission-v2",
    "sso-openid-connect"
  ]
}
```

---

### 4.2 Mock Token Response

**File:** `Tests/Fixtures/token-response.json`

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "patient/*.rs openid fhirUser offline_access",
  "patient": "patient-123",
  "encounter": "encounter-456",
  "fhirUser": "https://ehr.example.org/fhir/Practitioner/789",
  "need_patient_banner": true,
  "smart_style_url": "https://ehr.example.org/smart-style.json",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

---

### 4.3 Mock Patient Bundle

**File:** `Tests/Fixtures/patient-bundle.json`

```json
{
  "resourceType": "Bundle",
  "type": "searchset",
  "total": 3,
  "link": [
    {
      "relation": "self",
      "url": "https://fhir.example.org/Patient?_count=10"
    }
  ],
  "entry": [
    {
      "resource": {
        "resourceType": "Patient",
        "id": "1",
        "name": [{ "family": "Smith", "given": ["John"] }],
        "gender": "male",
        "birthDate": "1980-01-15"
      }
    },
    {
      "resource": {
        "resourceType": "Patient",
        "id": "2",
        "name": [{ "family": "Jones", "given": ["Alice"] }],
        "gender": "female",
        "birthDate": "1992-05-20"
      }
    },
    {
      "resource": {
        "resourceType": "Patient",
        "id": "3",
        "name": [{ "family": "Doe", "given": ["Jane"] }],
        "gender": "female",
        "birthDate": "1975-11-03"
      }
    }
  ]
}
```

---

## 5. Test Organization

### Directory Structure

```
Tests/
├── Unit/
│   ├── PKCETests.swift
│   ├── SMARTConfigurationTests.swift
│   ├── LaunchContextTests.swift
│   ├── AuthTests.swift
│   ├── ModelsR5ExtensionTests.swift
│   ├── PatientListQueryTests.swift
│   └── PatientListOrderTests.swift
├── Integration/
│   ├── ServerDiscoveryTests.swift
│   ├── OAuth2InterceptorTests.swift
│   ├── FHIROperationsTests.swift
│   ├── PatientListTests.swift
│   └── ClientAPITests.swift
├── E2E/
│   ├── SMARTSandboxTests.swift
│   └── OAuthFlowManualTests.swift
├── Mocks/
│   ├── MockHTTPClient.swift
│   ├── MockChain.swift
│   └── MockOAuth2.swift
├── Fixtures/
│   ├── smart-configuration.json
│   ├── token-response.json
│   ├── patient-bundle.json
│   ├── observation-bundle.json
│   └── metadata.json (CapabilityStatement)
└── Info.plist
```

---

## 6. Testing Strategy Summary

### Unit Tests (Fast, No Network)

**Coverage:** Pure logic, data transformations, parsing

| Component                  | Tests                                              | Priority |
| -------------------------- | -------------------------------------------------- | -------- |
| PKCE generation            | Generation, length, character set, S256 derivation | High     |
| SMARTConfiguration parsing | Minimal, full, unknown fields, well-known URL      | High     |
| LaunchContext parsing      | All fields, missing fields, extensions             | High     |
| Scope normalization        | v1→v2, launch scope injection, openid/profile      | High     |
| ModelsR5 extensions        | String, date, extensions filter, localization      | Medium   |

**Note:** PatientList, PatientListQuery, and PatientListOrder (from `Sources/helpers/`) are excluded from unit testing.

**Run command:**

```bash
swift test --filter Unit
```

---

### Integration Tests (Mock HTTP, No Auth)

**Coverage:** Component interactions, HTTP layer, parsing pipelines

| Component               | Tests                               | Priority |
| ----------------------- | ----------------------------------- | -------- |
| Server discovery        | Fetch, parse, cache, error handling | High     |
| OAuth2BearerInterceptor | Token injection, no token case      | High     |
| FHIRClient operations   | Raw, decoding, POST with body       | High     |
| Client API              | getJSON, getData, error responses   | Medium   |

**Note:** PatientList integration tests (from `Sources/helpers/`) are excluded.

**Run command:**

```bash
swift test --filter Integration
```

---

### End-to-End Tests (Real Network)

**Coverage:** Full flows against live servers

| Scenario               | Tests                           | Priority      |
| ---------------------- | ------------------------------- | ------------- |
| Discovery              | Fetch from SMART sandbox        | High          |
| Public resource access | Metadata, unauthenticated reads | Medium        |
| OAuth flows (manual)   | Standalone launch, EHR launch   | High (manual) |
| Token refresh          | With real refresh token         | Low (manual)  |

**Run command:**

```bash
swift test --filter E2E
# Manual tests:
swift test --filter E2EManual --enable-code-coverage
```

---

## 7. Mock Infrastructure

### MockHTTPClient Features

```swift
class MockHTTPClient: HTTPClient {
    // Record all requests for verification
    var recordedRequests: [URLRequest] = []

    // Configure responses by path
    var mockResponses: [String: (Data, Int)] = [:]

    // Simulate network delays
    var responseDelay: TimeInterval = 0

    // Simulate failures
    var shouldFail: Bool = false
    var failureError: HTTPClientError = .networkError("Mock failure")

    // Verify request details
    func lastRequest() -> URLRequest?
    func requestCount(for path: String) -> Int
    func hasAuthorizationHeader(in request: URLRequest) -> Bool
}
```

---

## 8. Continuous Integration Setup

### GitHub Actions Workflow

**File:** `.github/workflows/test.yml`

```yaml
name: Tests

on:
  push:
    branches: [main, update-r5]
  pull_request:
    branches: [main, update-r5]

jobs:
  unit-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.0.app

      - name: Run unit tests
        run: swift test --filter Unit --enable-code-coverage

      - name: Generate coverage report
        run: |
          xcrun llvm-cov export -format=lcov \
            .build/debug/SMARTPackageTests.xctest/Contents/MacOS/SMARTPackageTests \
            -instr-profile .build/debug/codecov/default.profdata > coverage.lcov

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.lcov

  integration-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.0.app

      - name: Run integration tests
        run: swift test --filter Integration

  e2e-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.0.app

      - name: Run E2E tests (non-manual)
        run: swift test --filter E2E --skip E2EManual
```

---

## 9. Test Coverage Goals

### Minimum Coverage Targets

| Category          | Target   | Notes                                 |
| ----------------- | -------- | ------------------------------------- |
| Unit tests        | 90%+     | Pure logic should be fully tested     |
| Integration tests | 70%+     | Cover main interaction paths          |
| E2E tests         | 50%+     | Verify critical flows work end-to-end |
| **Overall**       | **80%+** | Excluding generated code (ModelsR5)   |

### Critical Paths (Must Have 100% Coverage)

1. PKCE generation and verification
2. SMARTConfiguration parsing
3. LaunchContext parsing
4. Scope normalization (v1→v2)
5. OAuth2BearerInterceptor token injection

---

## 10. Testing Utilities

### Test Helpers

**File:** `Tests/Helpers/TestHelpers.swift`

```swift
import Foundation
import ModelsR5

class TestHelpers {

    static func createMockPatient(id: String, family: String, given: String, birthDate: Date? = nil) -> ModelsR5.Patient {
        let patient = ModelsR5.Patient()
        patient.id = FHIRPrimitive(FHIRString(id))

        let name = HumanName()
        name.family = FHIRPrimitive(FHIRString(family))
        name.given = [FHIRPrimitive(FHIRString(given))]
        patient.name = [name]

        if let birthDate {
            patient.birthDate = try? FHIRPrimitive(FHIRDate(date: birthDate))
        }

        return patient
    }

    static func createMockBundle(patients: [ModelsR5.Patient], total: Int? = nil) -> ModelsR5.Bundle {
        let bundle = ModelsR5.Bundle(type: FHIRPrimitive(.searchset))
        bundle.total = total.map { FHIRPrimitive(FHIRUnsignedInteger(Int32($0))) }

        bundle.entry = patients.map { patient in
            let entry = BundleEntry()
            entry.resource = .patient(patient)
            return entry
        }

        return bundle
    }

    /// Load JSON fixture using Bundle.module (SPM resources)
    /// Requires: resources: [.process("Fixtures")] in Package.swift test target
    static func loadFixture(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture '\(name).json' not found in Bundle.module")
        }
        return try Data(contentsOf: url)
    }
}
```

---

## 11. Performance Tests

### Benchmark Tests

**File:** `Tests/Performance/PerformanceTests.swift`

```swift
import XCTest
@testable import SMART

class PerformanceTests: XCTestCase {

    func testPKCEGenerationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = PKCE.generate()
            }
        }
    }

    func testScopeNormalizationPerformance() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)
        let properties = SMARTAuthProperties()

        measure {
            for _ in 0..<1000 {
                _ = auth.updatedScope(from: "patient/*.read user/*.write openid fhirUser", properties: properties)
            }
        }
    }

    func testBundleParsingPerformance() throws {
        let bundleData = TestHelpers.loadFixture(named: "large-patient-bundle")
        let decoder = JSONDecoder()

        measure {
            _ = try? decoder.decode(ModelsR5.Bundle.self, from: bundleData)
        }
    }
}
```

---

## 12. Snapshot/Regression Tests

### Configuration Snapshot Tests

**File:** `Tests/Snapshots/ConfigurationSnapshotTests.swift`

```swift
import XCTest
@testable import SMART

class ConfigurationSnapshotTests: XCTestCase {

    func testSMARTConfigurationDecodingStability() throws {
        let fixture = try TestHelpers.loadFixture(named: "smart-configuration")

        let config1 = try JSONDecoder().decode(SMARTConfiguration.self, from: fixture)
        let encoded = try JSONEncoder().encode(config1)
        let config2 = try JSONDecoder().decode(SMARTConfiguration.self, from: encoded)

        // Round-trip should produce identical values
        XCTAssertEqual(config1.authorizationEndpoint, config2.authorizationEndpoint)
        XCTAssertEqual(config1.tokenEndpoint, config2.tokenEndpoint)
        XCTAssertEqual(config1.capabilities, config2.capabilities)
    }
}
```

---

## 13. Test Execution Plan

### Phase 1: Foundation (Week 1)

1. ✅ Set up test targets in Package.swift
2. ✅ Create mock infrastructure (MockHTTPClient, MockChain)
3. ✅ Write unit tests for PKCE
4. ✅ Write unit tests for SMARTConfiguration
5. ✅ Write unit tests for LaunchContext

### Phase 2: Core Logic (Week 2)

1. ✅ Write unit tests for scope normalization
2. ✅ Write unit tests for ModelsR5 extensions
3. ✅ Write integration tests for OAuth2BearerInterceptor
4. ✅ Write integration tests for Server discovery

**Note:** PatientListQuery tests removed (helpers directory excluded from testing).

### Phase 3: API Layer (Week 3)

1. ✅ Write integration tests for FHIRClient operations
2. ✅ Write integration tests for Client API methods
3. ✅ Write E2E tests against SMART sandbox
4. ✅ Write performance benchmarks

**Note:** PatientList integration tests removed (helpers directory excluded from testing).

### Phase 4: Validation (Week 4)

1. ✅ Achieve 80%+ code coverage
2. ✅ Run against multiple SMART servers
3. ✅ Manual OAuth flow testing
4. ✅ Documentation of test failures and edge cases
5. ✅ Performance regression baseline

---

## 14. Quick Test Commands

```bash
# Run all tests
swift test

# Run specific test classes (name-based filtering, not folder-based)
swift test --filter PKCETests
swift test --filter SMARTConfigurationTests
swift test --filter LocalSMARTTests

# Run specific test method
swift test --filter PKCETests/testPKCEGeneration

# Run manual OAuth tests (requires environment variable)
RUN_MANUAL_OAUTH=1 swift test --filter OAuthFlowManualTests

# Run with coverage
swift test --enable-code-coverage

# Run on iOS simulator
xcodebuild test -scheme SwiftSMART-iOS -destination 'platform=iOS Simulator,name=iPhone 15'

# Run on macOS
swift test
```

**Note:** `--filter` matches test class/method names using regex, not folder names. For folder-based organization, consider separate test targets.

---

## 15. Test Data Management

### Sensitive Test Data

For OAuth flow tests that require real credentials:

**File:** `Tests/Credentials.swift.template`

```swift
// Copy this to Credentials.swift and fill in your values
// Credentials.swift is gitignored

struct TestCredentials {
    static let sandboxClientID = "YOUR_CLIENT_ID"
    static let sandboxRedirectURI = "YOUR_REDIRECT"
    static let sandboxFHIRBaseURL = "https://launch.smarthealthit.org/v/r4/fhir"
}
```

**File:** `.gitignore` (add)

```
Tests/Credentials.swift
```

---

## 16. Continuous Testing Matrix

### Test Against Multiple Configurations

| Configuration | Purpose                         |
| ------------- | ------------------------------- |
| iOS 13+       | Minimum supported iOS version   |
| iOS 17+       | Latest iOS features             |
| macOS 12+     | Minimum supported macOS version |
| macOS 14+     | Latest macOS features           |
| Swift 5.5     | Minimum supported Swift version |
| Swift 5.9+    | Latest Swift features           |

---

## Summary: Recommended Testing Approach

### Priority 1 (Immediate):

1. **Unit tests for PKCE** - Critical security component
2. **Unit tests for configuration parsing** - Foundation for discovery
3. **Unit tests for launch context** - Core SMART feature
4. **Unit tests for scope normalization** - Ensures v1/v2 compatibility
5. **Integration tests for discovery** - Mock HTTP responses

### Priority 2 (Next Sprint):

1. **Integration tests for OAuth interceptor** - Token injection
2. **Integration tests for FHIR operations** - API access layer
3. **E2E tests against sandbox** - Validate real-world usage

**Note:** PatientList tests removed (helpers directory excluded).

### Priority 3 (Polish):

1. **Performance benchmarks** - Prevent regressions
2. **Manual OAuth flow tests** - Document user flows
3. **Cross-platform tests** - iOS/macOS compatibility
4. **Snapshot tests** - Detect unintended API changes

### Test Metrics:

- **Target: 80%+ overall coverage**
- **Critical paths: 100% coverage**
- **Build time: <5 minutes for all tests**
- **E2E tests: <2 minutes (excluding manual)**

This strategy balances comprehensive coverage with maintainability and fast feedback loops.
