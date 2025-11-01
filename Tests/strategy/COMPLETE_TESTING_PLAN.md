# Complete Testing Strategy Implementation

## Overview

Comprehensive testing plan for Swift-SMART library with **technical corrections** from detailed verification pass:

✅ **Key Fixes Applied:**

1. SPM resources configuration for fixtures (`Bundle.module`)
2. Test filtering clarification (name-based, not folder-based)
3. SMART v2 scope rules (`openid + fhirUser`, not `profile`)
4. RFC 7636 PKCE compliance (S256, 43-128 char verifier)
5. Exact `.well-known/smart-configuration` discovery URL
6. Environment-gated manual tests
7. **Helpers directory exclusion** (PatientList, PatientListQuery, PatientListOrder)

---

## Phase 1: Foundation & Test Infrastructure

### 1.1 Update Package.swift ✅ CORRECTED

Add test target with **resources for fixtures** (critical for CI/Linux):

```swift
.testTarget(
    name: "SMARTTests",
    dependencies: [
        "SMART",
        "FHIRClient",
        "HTTPClient",
        .product(name: "ModelsR5", package: "FHIRModels"),
    ],
    path: "Tests",
    resources: [.process("Fixtures")]  // ✅ Required for Bundle.module
)
```

**Without `resources:`**, JSON fixtures won't be available in CI environments.

### 1.2 Create Directory Structure

```
Tests/
├── Unit/              (Pure logic, no network)
├── Integration/       (Mock HTTP, component interactions)
├── E2E/              (Live server tests)
├── Mocks/            (Mock implementations)
├── Fixtures/         (JSON test data - loaded via Bundle.module)
├── Helpers/          (Test utilities)
└── Performance/      (Benchmark tests)
```

### 1.3 Build Mock Infrastructure

**Tests/Mocks/MockHTTPClient.swift**

```swift
import Combine
import Foundation
import HTTPClient

class MockHTTPClient: HTTPClient {
    var interceptors: [Interceptor] = []
    var recordedRequests: [URLRequest] = []
    var mockResponses: [String: (Data, Int)] = [:]  // path -> (data, statusCode)

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
            _ = cancellable
        }
    }
}
```

**Tests/Mocks/MockChain.swift**

```swift
import Combine
import Foundation
import HTTPClient

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

## Phase 2: Priority 1 - Critical Unit Tests

### 2.1 PKCE Tests (Tests/Unit/PKCETests.swift) ✅ RFC 7636 Compliant

Test `Sources/Client/PKCE.swift`:

**RFC 7636 Requirements:**

- Verifier: 43-128 characters from `[A-Za-z0-9-._~]`
- Challenge: `BASE64URL(SHA256(verifier))` - no `+`, `/`, `=`
- Method: `S256` (required by SMART servers)

**Test Cases:**

```swift
import XCTest
@testable import SMART

class PKCETests: XCTestCase {

    func testPKCEGeneration() {
        let pkce = PKCE.generate()

        XCTAssertEqual(pkce.codeVerifier.count, 64)  // Default length
        XCTAssertFalse(pkce.codeChallenge.isEmpty)
        XCTAssertFalse(pkce.codeChallenge.contains("+"))
        XCTAssertFalse(pkce.codeChallenge.contains("/"))
        XCTAssertFalse(pkce.codeChallenge.contains("="))
        XCTAssertEqual(pkce.method, "S256")
    }

    func testPKCECustomLength() {
        let pkce43 = PKCE.generate(length: 43)
        XCTAssertEqual(pkce43.codeVerifier.count, 43)

        let pkce128 = PKCE.generate(length: 128)
        XCTAssertEqual(pkce128.codeVerifier.count, 128)

        // Out of bounds should clamp to RFC 7636 range
        let pkceTooShort = PKCE.generate(length: 10)
        XCTAssertEqual(pkceTooShort.codeVerifier.count, 43)

        let pkceTooLong = PKCE.generate(length: 200)
        XCTAssertEqual(pkceTooLong.codeVerifier.count, 128)
    }

    func testPKCEVerifierCharacterSet() {
        let pkce = PKCE.generate()
        let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

        for char in pkce.codeVerifier.unicodeScalars {
            XCTAssertTrue(allowedChars.contains(char), "Invalid character: \(char)")
        }
    }

    // ✅ Known test vector from RFC 7636 Appendix B
    func testPKCEKnownVector() {
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

### 2.2 SMARTConfiguration Tests (Tests/Unit/SMARTConfigurationTests.swift)

Test `Sources/Client/SMARTConfiguration.swift`:

**Key Validations:**

- Exact discovery URL: `{base}/.well-known/smart-configuration`
- Required: `authorization_endpoint`, `token_endpoint`
- Optional: `code_challenge_methods_supported` (should include `"S256"`)
- Preserve unknown fields in `additionalFields`

**Test Cases:**

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
    }

    func testFullConfigurationWithPKCE() throws {
        let json = """
        {
            "authorization_endpoint": "https://ehr.example.org/auth/authorize",
            "token_endpoint": "https://ehr.example.org/auth/token",
            "capabilities": ["launch-ehr", "permission-patient", "client-public"],
            "code_challenge_methods_supported": ["S256"]
        }
        """

        let config = try JSONDecoder().decode(SMARTConfiguration.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(config.capabilities?.count, 3)
        XCTAssertTrue(config.codeChallengeMethodsSupported?.contains("S256") ?? false)
    }

    func testWellKnownURL() {
        let baseURL = URL(string: "https://fhir.example.org/fhir")!
        let wellKnown = SMARTConfiguration.wellKnownURL(for: baseURL)

        // ✅ Exact path per SMART spec
        XCTAssertEqual(wellKnown.absoluteString, "https://fhir.example.org/fhir/.well-known/smart-configuration")
    }

    func testAdditionalFieldsPreserved() throws {
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
}
```

**Fixture:** `Tests/Fixtures/smart-configuration.json`

---

### 2.3 LaunchContext Tests (Tests/Unit/LaunchContextTests.swift)

Test `Sources/Client/LaunchContext.swift`:

**SMART Launch Context Fields:**

- `patient`, `encounter`, `fhirUser` (identity)
- UI hints: `need_patient_banner`, `smart_style_url`
- Extensions: `intent`, `tenant`, `location`, `fhirContext` array

**Test Cases:**

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
            "fhirContext": [
                {"reference": "ServiceRequest/sr-1"}
            ]
        }
        """

        let context = try JSONDecoder().decode(LaunchContext.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(context.patient, "patient-123")
        XCTAssertEqual(context.encounter, "encounter-456")
        XCTAssertEqual(context.user?.absoluteString, "https://ehr.example.org/fhir/Practitioner/789")
        XCTAssertEqual(context.needPatientBanner, true)
        XCTAssertEqual(context.intent, "reconcile-medications")
        XCTAssertEqual(context.fhirContext?.count, 1)
    }
}
```

**Fixture:** `Tests/Fixtures/launch-context.json`

---

### 2.4 Scope Normalization Tests (Tests/Unit/AuthTests.swift) ✅ SMART v2 Spec

Test `Sources/Client/Auth.swift` scope handling:

**SMART v2 Scopes (FHIR.dev scopes-v2):**

- `.rs` = read + search
- `.cruds` = create + read + update + delete + search
- **Identity:** `openid` + `fhirUser` (always required)
- `profile` is **optional** (only if OIDC profile claims needed)

**v1 → v2 Conversion:**

- `*.read` → `*.rs`
- `*.write` → `*.cruds`
- **Context-aware:** Preserve `patient/` vs `user/` prefix

**Test Cases:**

```swift
import XCTest
@testable import SMART

class AuthTests: XCTestCase {

    func testScopeNormalizationV1ToV2() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        let properties = SMARTAuthProperties()

        // v1 -> v2 conversion (context-aware)
        let normalized = auth.updatedScope(from: "patient/Observation.read", properties: properties)
        XCTAssertTrue(normalized.contains("patient/Observation.rs"))
        XCTAssertFalse(normalized.contains(".read"))
    }

    func testScopeAlwaysAddsOpenIDAndFHIRUser() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        let properties = SMARTAuthProperties()
        let scopes = auth.updatedScope(from: nil, properties: properties)

        // ✅ SMART v2 requirement
        XCTAssertTrue(scopes.contains("openid"))
        XCTAssertTrue(scopes.contains("fhirUser"))
        // profile is OPTIONAL, not required
    }

    func testScopeAddsLaunchContext() {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: nil)

        var properties = SMARTAuthProperties()
        properties.granularity = .launchContext

        let scopes = auth.updatedScope(from: "patient/*.rs", properties: properties)
        XCTAssertTrue(scopes.contains("launch"))
    }
}
```

**Reference:** FHIR.dev - SMART App Launch 2.x scope patterns

---

### 2.5 ModelsR5 Extension Tests (Tests/Unit/ModelsR5ExtensionTests.swift)

Test `Sources/Client/ModelsR5+SMART.swift`:

**Key Extensions:**

- `FHIRPrimitive<FHIRString>.string` convenience
- `FHIRPrimitive<FHIRDate>.nsDate` conversion
- `Element.extensions(for:)` filtering
- `String.fhir_localized` wrapper

**Test Cases:**

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

        // ✅ Add timezone edge case tests
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
}
```

---

## Phase 3: Priority 1 - Integration Tests with Mocks

### 3.1 Server Discovery Tests (Tests/Integration/ServerDiscoveryTests.swift)

Test `Sources/Client/Server.swift` discovery using `MockHTTPClient`:

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
                "capabilities": ["launch-ehr", "client-public"],
                "code_challenge_methods_supported": ["S256"]
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
                XCTAssertTrue(config.codeChallengeMethodsSupported?.contains("S256") ?? false)
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

        let exp2 = expectation(description: "Second fetch (cached)")
        server.getSMARTConfiguration { _ in exp2.fulfill() }
        waitForExpectations(timeout: 5)

        // Should not make another HTTP request
        XCTAssertEqual(mockHTTP.recordedRequests.count, requestCount1)
    }
}
```

---

### 3.2 OAuth2BearerInterceptor Tests (Tests/Integration/OAuth2InterceptorTests.swift)

```swift
import XCTest
import HTTPClient
@testable import SMART

class OAuth2InterceptorTests: XCTestCase {

    func testInterceptorAddsAuthorizationHeader() async throws {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .codeGrant, server: server, settings: ["client_id": "test"])

        auth.oauth = OAuth2CodeGrant(settings: ["client_id": "test"])
        auth.oauth?.clientConfig.accessToken = "test-token-123"

        let interceptor = OAuth2BearerInterceptor(auth: auth)

        let mockChain = MockChain(request: URLRequest(url: URL(string: "https://fhir.example.org/Patient")!))

        _ = try await interceptor.interceptAsync(chain: mockChain)

        XCTAssertEqual(mockChain.modifiedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-123")
    }

    func testInterceptorWithoutToken() async throws {
        let server = Server(baseURL: URL(string: "https://fhir.example.org")!)
        let auth = Auth(type: .none, server: server, settings: nil)

        let interceptor = OAuth2BearerInterceptor(auth: auth)

        let mockChain = MockChain(request: URLRequest(url: URL(string: "https://fhir.example.org/Patient")!))

        _ = try await interceptor.interceptAsync(chain: mockChain)

        XCTAssertNil(mockChain.modifiedRequest?.value(forHTTPHeaderField: "Authorization"))
    }
}
```

---

### 3.3 FHIR Operations Tests (Tests/Integration/FHIROperationsTests.swift)

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

        let expectation = self.expectation(description: "Decoding completes")

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

## Phase 4: Priority 2 - E2E Tests Against Real Server

### 4.1 Local SMART Launcher Tests (Tests/E2E/LocalSMARTTests.swift) ✅ CORRECTED

Test against `http://localhost:8080/v/r5/sim/.../fhir` - **URL provided at test runtime**

```swift
import XCTest
import Combine
@testable import SMART

class LocalSMARTTests: XCTestCase {

    // ✅ URL configurable via environment or test setup
    let sandboxURL = ProcessInfo.processInfo.environment["SMART_LAUNCHER_URL"]
        ?? "http://localhost:8080/v/r5/sim/WzIsIjAzZDI5NGRiLTJjY2ItNDZkYi04NTIwLWE2MjJhNmU2MDUzZCIsIiIsIk1BTlVBTCIsMCwwLDAsIiIsIiIsIiIsIiIsIiIsIiIsIiIsMCwxLCIiXQ/fhir"

    var cancellables = Set<AnyCancellable>()

    func testDiscoveryAgainstRealServer() throws {
        guard let baseURL = URL(string: sandboxURL) else {
            throw XCTSkip("Invalid SMART Launcher URL")
        }

        let server = Server(baseURL: baseURL)

        let expectation = self.expectation(description: "Discovery from real server")

        server.getSMARTConfiguration { result in
            switch result {
            case .success(let config):
                // ✅ Exact path: {base}/.well-known/smart-configuration
                XCTAssertNotNil(config.authorizationEndpoint)
                XCTAssertNotNil(config.tokenEndpoint)

                // ✅ RFC 7636: SMART servers MUST support S256
                XCTAssertTrue(config.codeChallengeMethodsSupported?.contains("S256") ?? false,
                             "SMART server must support PKCE S256")

                expectation.fulfill()
            case .failure(let error):
                XCTFail("Discovery failed: \(error)")
            }
        }

        waitForExpectations(timeout: 10)
    }

    func testPublicMetadataAccess() throws {
        guard let baseURL = URL(string: sandboxURL) else {
            throw XCTSkip("Invalid SMART Launcher URL")
        }

        let server = Server(baseURL: baseURL)

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
                    // ✅ Verify R5 FHIR version
                    XCTAssertTrue(capability.fhirVersion?.value.rawValue.starts(with: "5.0") ?? false,
                                 "Expected FHIR R5 (5.0.x)")
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

### 4.2 Manual OAuth Flow Tests (Tests/E2E/OAuthFlowManualTests.swift) ✅ ENVIRONMENT-GATED

```swift
import XCTest
@testable import SMART

class OAuthFlowManualTests: XCTestCase {

    func testStandaloneLaunchFlow() throws {
        // ✅ Environment gate for manual tests
        guard ProcessInfo.processInfo.environment["RUN_MANUAL_OAUTH"] == "1" else {
            throw XCTSkip("Manual OAuth disabled. Set RUN_MANUAL_OAUTH=1 to enable.")
        }

        let client = Client(
            baseURL: URL(string: "http://localhost:8080/v/r5/sim/.../fhir")!,
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
    }
}
```

**Run manually:**

```bash
RUN_MANUAL_OAUTH=1 swift test --filter OAuthFlowManualTests
```

---

## Phase 5: Test Helpers & Fixtures

### 5.1 Test Helpers (Tests/Helpers/TestHelpers.swift) ✅ Bundle.module

```swift
import Foundation
import ModelsR5
import XCTest

class TestHelpers {

    /// Load JSON fixture from Tests/Fixtures/ using Bundle.module (SPM resources)
    /// Requires: resources: [.process("Fixtures")] in Package.swift
    static func loadFixture(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture '\(name).json' not found in Bundle.module")
        }
        return try Data(contentsOf: url)
    }

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
}
```

---

### 5.2 Fixtures

Create JSON fixtures in `Tests/Fixtures/`:

1. **smart-configuration.json** - Full SMART config
2. **token-response.json** - OAuth token with launch context
3. **patient-bundle.json** - Bundle with 3 patients
4. **single-patient.json** - Individual patient
5. **metadata.json** - CapabilityStatement (R5)
6. **large-patient-bundle.json** - 100+ patients for performance

**All loaded via `Bundle.module` (requires `resources:` in Package.swift)**

---

## Phase 6: Priority 3 - Performance & Polish

### 6.1 Performance Tests (Tests/Performance/PerformanceTests.swift)

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
        let bundleData = try TestHelpers.loadFixture(named: "large-patient-bundle")
        let decoder = JSONDecoder()

        measure {
            _ = try? decoder.decode(ModelsR5.Bundle.self, from: bundleData)
        }
    }
}
```

---

### 6.2 Snapshot Tests (Tests/Snapshots/ConfigurationSnapshotTests.swift)

```swift
import XCTest
@testable import SMART

class ConfigurationSnapshotTests: XCTestCase {

    func testSMARTConfigurationRoundTrip() throws {
        let fixture = try TestHelpers.loadFixture(named: "smart-configuration")

        let config1 = try JSONDecoder().decode(SMARTConfiguration.self, from: fixture)
        let encoded = try JSONEncoder().encode(config1)
        let config2 = try JSONDecoder().decode(SMARTConfiguration.self, from: encoded)

        XCTAssertEqual(config1.authorizationEndpoint, config2.authorizationEndpoint)
        XCTAssertEqual(config1.tokenEndpoint, config2.tokenEndpoint)
        XCTAssertEqual(config1.capabilities, config2.capabilities)
    }
}
```

---

### 6.3 Cross-Platform Tests

- iOS 13+ (CryptoKit available iOS 13+)
- macOS 12+ (CryptoKit available macOS 10.15+, safely covered by 12+)
- **Add FHIRDate timezone edge case tests** (date-only vs date-time)

---

## Phase 7: CI/CD Pipeline

### 7.1 GitHub Actions Workflow (.github/workflows/test.yml)

```yaml
name: Tests

on:
  push:
    branches: [main, update-r5]
  pull_request:
    branches: [main, update-r5]

jobs:
  unit-tests:
    runs-on: macos-14 # Xcode 15+
    steps:
      - uses: actions/checkout@v3

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.0.app

      - name: Run unit tests
        run: swift test --filter PKCETests --filter SMARTConfigurationTests --filter LaunchContextTests --enable-code-coverage

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
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v3

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.0.app

      - name: Run integration tests
        run: swift test --filter ServerDiscoveryTests --filter OAuth2InterceptorTests --filter FHIROperationsTests

  e2e-tests:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v3

      - name: Select Xcode version
        run: sudo xcode-select -s /Applications/Xcode_15.0.app

      - name: Run E2E tests (non-manual)
        run: swift test --filter LocalSMARTTests
        env:
          SMART_LAUNCHER_URL: "http://localhost:8080/v/r5/sim/WzIsIjAzZDI5NGRiLTJjY2ItNDZkYi04NTIwLWE2MjJhNmU2MDUzZCIsIiIsIk1BTlVBTCIsMCwwLDAsIiIsIiIsIiIsIiIsIiIsIiIsIiIsMCwxLCIiXQ/fhir"
```

---

## Phase 8: Documentation & Cleanup

### 8.1 Update README.md ✅ CORRECTED TEST FILTERING

```markdown
## Testing

# Run all tests

swift test

# Run specific test classes (name-based filtering, not folder-based)

swift test --filter PKCETests
swift test --filter SMARTConfigurationTests
swift test --filter LocalSMARTTests

# Run manual OAuth tests (requires environment variable)

RUN_MANUAL_OAUTH=1 swift test --filter OAuthFlowManualTests

# With coverage

swift test --enable-code-coverage

# Generate coverage report

xcrun llvm-cov report .build/debug/SMARTPackageTests.xctest/Contents/MacOS/SMARTPackageTests \
 -instr-profile .build/debug/codecov/default.profdata
```

**Note:** `--filter` matches test class/method names (regex), not folder names.

---

### 8.2 Cleanup

- Remove old `Tests/ClientTests.swift` and `Tests/ServerTests.swift`
- Move `Tests/metadata` to `Tests/Fixtures/metadata.json`

---

## Implementation Order (Revised)

1. **Day 1-2:** Package.swift (with `resources:`) + Mock infrastructure + PKCE tests + SMARTConfiguration tests
2. **Day 3-4:** LaunchContext + Scope normalization (`openid`+`fhirUser`) + ModelsR5 extension tests
3. **Day 5:** Test helpers (`Bundle.module`) + Fixtures creation
4. **Day 6-7:** Integration tests (discovery, OAuth interceptor, FHIR operations)
5. **Day 8:** E2E tests against local SMART launcher
6. **Day 9:** Performance tests + Snapshot tests
7. **Day 10:** CI/CD setup (GitHub Actions with coverage)
8. **Day 11:** Cross-platform validation (iOS/macOS) + FHIRDate timezone edge cases
9. **Day 12:** Final polish, coverage review, cleanup

---

## Critical Success Metrics

- ✅ 80%+ code coverage overall (excluding `Sources/helpers/`)
- ✅ 100% coverage for PKCE, SMARTConfiguration, LaunchContext, scope normalization
- ✅ All tests pass on iOS 13+ and macOS 12+
- ✅ E2E tests validate against local R5 SMART server
- ✅ CI pipeline runs in <5 minutes
- ✅ Zero test flakiness (deterministic results)
- ✅ RFC 7636 PKCE compliance (S256, 43-128 verifier)
- ✅ SMART v2 scope compliance (`openid`+`fhirUser`, `.rs`/`.cruds`)

---

## Exclusions (Helpers Directory)

**`Sources/helpers/` directory EXCLUDED from testing:**

- PatientList.swift
- PatientListQuery.swift
- PatientListOrder.swift
- iOS/Auth+iOS.swift
- iOS/PatientList+iOS.swift
- macOS/Auth+macOS.swift

These presentation layer helpers will be validated through manual testing and integration QA.

---

## Key Technical Corrections Applied

1. ✅ **SPM resources:** `resources: [.process("Fixtures")]` in Package.swift
2. ✅ **Test filtering:** Name-based, not folder-based
3. ✅ **SMART v2 scopes:** `openid`+`fhirUser` (not `profile`)
4. ✅ **RFC 7636 PKCE:** S256, 43-128 verifier, known test vector
5. ✅ **Discovery URL:** Exact `{base}/.well-known/smart-configuration`
6. ✅ **Manual tests:** Environment-gated with `RUN_MANUAL_OAUTH=1`
7. ✅ **Helpers exclusion:** PatientList components removed from plan
