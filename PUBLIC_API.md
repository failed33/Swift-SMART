# Swift-SMART Public API Reference

## Overview

Swift-SMART is a Swift library that enables iOS and macOS applications to implement SMART App Launch for connecting to FHIR R5 servers with OAuth2 authorization.

---

## Public Classes and Structs

### 1. `Client` - Main Entry Point

The primary interface for SMART on FHIR authorization and FHIR API access.

```swift
import SMART

// Initialize
let client = Client(
    baseURL: URL(string: "https://fhir.example.org")!,
    settings: [
        "client_id": "my-app-id",           // Your registered client ID
        "redirect": "myapp://callback",      // Your redirect URI
        "scope": "patient/*.rs offline_access openid fhirUser"
    ]
)
```

#### Properties

```swift
public let server: Server                           // The FHIR server instance
public var authProperties: SMARTAuthProperties      // Authorization behavior configuration
public var awaitingAuthCallback: Bool { get }       // Whether auth is in progress
```

#### Methods

##### **Standalone Launch**

```swift
open func authorize(callback: @escaping (_ patient: ModelsR5.Patient?, _ error: Error?) -> Void)
```

Initiates authorization flow from outside the EHR. If `launch/patient` scope is included, user will be prompted to select a patient.
The library automatically:

- Discovers `.well-known/smart-configuration` (cached between calls)
- Adds `aud=<FHIR base URL>` to every authorization request
- Enforces PKCE with `code_challenge_method=S256` and fails fast if the server configuration omits support
- Includes the `launch` parameter when `handleEHRLaunch(iss:launch:)` has been called; otherwise the request is treated as standalone with no `launch`

**Example:**

```swift
client.authorize { patient, error in
    guard let patient = patient, error == nil else {
        print("Authorization failed: \(error)")
        return
    }
    print("Authorized with patient: \(patient.id)")
    // Now access FHIR API via client.server.fhirClient
}
```

##### **EHR Launch**

```swift
open func handleEHRLaunch(
    iss: String,
    launch: String,
    additionalSettings: OAuth2JSON? = nil,
    completion: @escaping (Error?) -> Void
)
```

Handles launch parameters from an EHR (`iss` = FHIR base URL, `launch` = opaque context token).
Call this before `authorize(...)` to ensure the subsequent authorization request includes the `launch` parameter and `launch` scope automatically.

**Example:**

```swift
// App receives iss and launch from URL params
client.handleEHRLaunch(iss: issuer, launch: launchToken) { error in
    guard error == nil else { return }

    // Now call authorize to complete the flow
    client.authorize { patient, error in
        // Authorized with EHR-provided context
    }
}
```

##### **OAuth Redirect Handling**

```swift
open func didRedirect(to url: URL) -> Bool
```

Call this from your app delegate when intercepting the OAuth callback URL.

**Example (iOS):**

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return client.didRedirect(to: url)
}
```

##### **Server Readiness**

```swift
open func ready(callback: @escaping (Error?) -> Void)
```

Ensures the server has fetched `.well-known/smart-configuration` and is ready for authorization.

##### **Session Management**

```swift
open func abort()                           // Cancel ongoing auth
open func reset()                           // Clear all auth state and tokens
open func forgetClientRegistration()        // Clear client registration
```

##### **FHIR Data Access**

```swift
open func getJSON(at path: String, completion: @escaping (Result<FHIRClient.Response, Error>) -> Void)
open func getData(from url: URL, accept: String, completion: @escaping (Result<FHIRClient.Response, Error>) -> Void)
```

**Example:**

```swift
client.getJSON(at: "Patient/123") { result in
    switch result {
    case .success(let response):
        let patient = try? JSONDecoder().decode(ModelsR5.Patient.self, from: response.body)
    case .failure(let error):
        print("Request failed: \(error)")
    }
}
```

---

### 2. `Server` - FHIR Server Connection

Represents a FHIR server with OAuth2 authorization. Usually accessed via `client.server`.

#### Properties

```swift
public let baseURL: URL                                 // FHIR server base URL
public let aud: String                                  // Audience parameter for OAuth
public var name: String? { get }                        // Server name from metadata
public var idToken: String? { get }                     // OpenID Connect ID token
public var refreshToken: String? { get }                // OAuth refresh token
public var launchContext: LaunchContext? { get }        // Parsed launch context
public var fhirClient: FHIRClient { get }               // Direct FHIR API client
public var logger: OAuth2Logger?                        // Optional logging
public var onBeforeDynamicClientRegistration: ((URL) -> OAuth2DynReg)?
```

#### Methods

##### **Discovery**

```swift
open func getSMARTConfiguration(
    forceRefresh: Bool = false,
    completion: @escaping (Result<SMARTConfiguration, Error>) -> Void
)
```

Fetches and caches `.well-known/smart-configuration`.
`Server.ready` will fail early if the configuration omits `code_challenge_methods_supported = ["S256"]`, matching SMART App Launch requirements.

##### **Patient Fetch**

```swift
func fetchPatient(id: String, completion: @escaping (Result<ModelsR5.Patient, Error>) -> Void)
```

Convenience method to read a Patient resource by ID.

**Example:**

```swift
server.fetchPatient(id: "123") { result in
    switch result {
    case .success(let patient):
        print("Patient name: \(patient.displayNameFamilyGiven)")
    case .failure(let error):
        print("Fetch failed: \(error)")
    }
}
```

##### **Direct FHIRClient Access**

```swift
server.fhirClient.execute(operation: myOperation)
```

For advanced use cases, execute any `FHIRClientOperation` directly.

---

### 3. `SMARTAuthProperties` - Authorization Configuration

Controls authorization behavior.

```swift
public struct SMARTAuthProperties {
    public var embedded: Bool = true                        // Use embedded webview vs browser
    public var granularity: SMARTAuthGranularity = .patientSelectNative
}

public enum SMARTAuthGranularity {
    case tokenOnly              // Just get tokens, no context
    case launchContext          // Request EHR-provided context (EHR launch)
    case patientSelectWeb       // Patient selection in EHR webview
    case patientSelectNative    // Patient selection in native UI (iOS only)
}
```

**Example:**

```swift
client.authProperties.embedded = false              // Use Safari instead of webview
client.authProperties.granularity = .patientSelectWeb
```

---

### 4. `LaunchContext` - SMART Launch Context

Parsed from OAuth token response; available at `client.server.launchContext`.

```swift
public struct LaunchContext: Codable {
    public let patient: String?                     // Patient ID
    public let encounter: String?                   // Encounter ID
    public let user: URL?                           // fhirUser (URL to Practitioner, Patient, etc.)
    public let needPatientBanner: Bool?             // UX hint: show patient banner
    public let smartStyleURL: URL?                  // URL to style JSON
    public let intent: String?                      // App launch intent
    public let tenant: String?                      // Organization/tenant ID
    public let location: String?                    // Location context
    public let fhirContext: [AnyCodable]?           // Additional FHIR context items
    public let additionalFields: [String: AnyCodable]  // Extensibility
}
```

**Example:**

```swift
if let context = client.server.launchContext {
    print("Patient ID: \(context.patient ?? "none")")
    print("Encounter ID: \(context.encounter ?? "none")")
    print("Need patient banner: \(context.needPatientBanner ?? false)")
}
```

---

### 5. `SMARTConfiguration` - Discovery Document

Parsed from `.well-known/smart-configuration`; available via `server.getSMARTConfiguration()`.

```swift
public struct SMARTConfiguration: Codable {
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let registrationEndpoint: URL?
    public let capabilities: [String]?
    public let scopesSupported: [String]?
    public let codeChallengeMethodsSupported: [String]?
    // ... 15+ additional properties
}
```

**Example:**

```swift
server.getSMARTConfiguration { result in
    switch result {
    case .success(let config):
        print("Auth endpoint: \(config.authorizationEndpoint)")
        print("Capabilities: \(config.capabilities ?? [])")
    case .failure(let error):
        print("Discovery failed: \(error)")
    }
}
```

---

### 6. `PatientList` - Patient Search & Display

Manages paginated patient lists with search and ordering.

```swift
open class PatientList {
    public var status: PatientListStatus { get }
    public var onStatusUpdate: ((Error?) -> Void)?
    public var onPatientUpdate: (() -> Void)?
    public var expectedNumberOfPatients: UInt { get }
    public var actualNumberOfPatients: UInt { get }
    public var hasMore: Bool { get }
    public var order: PatientListOrder
    public let query: PatientListQuery

    public init(query: PatientListQuery)

    open func retrieve(fromServer: Server)
    open func retrieveMore(fromServer: Server)

    subscript(index: Int) -> PatientListSection? { get }
}

open class PatientListAll: PatientList {
    public init()  // Searches for all patients
}
```

**Example:**

```swift
let patientList = PatientListAll()
patientList.order = .nameFamilyASC
patientList.onPatientUpdate = {
    print("Loaded \(patientList.actualNumberOfPatients) patients")
}
patientList.retrieve(fromServer: client.server)
```

---

### 7. `PatientListQuery` - Search Query Builder

```swift
public final class PatientListQuery {
    public init(pageSize: Int = 50, additionalParameters: [URLQueryItem] = [])
    public func reset()
}
```

**Example:**

```swift
let query = PatientListQuery(
    pageSize: 100,
    additionalParameters: [
        URLQueryItem(name: "family", value: "Smith"),
        URLQueryItem(name: "birthdate", value: "gt1990-01-01")
    ]
)
let patientList = PatientList(query: query)
```

---

### 8. `PatientListOrder` - Patient Sorting

```swift
public enum PatientListOrder: String {
    case nameGivenASC = "given,family,birthdate"
    case nameFamilyASC = "family,given,birthdate"
    case birthDateASC = "birthdate,family,given"

    func ordered(_ patients: [ModelsR5.Patient]) -> [ModelsR5.Patient]
}
```

---

### 9. ModelsR5 Extensions

Convenience accessors for FHIR R5 primitives (compatible with old Swift-FHIR patterns).

#### FHIRPrimitive<FHIRString>

```swift
extension FHIRPrimitive where PrimitiveType == FHIRString {
    public var string: String { get }                   // Returns value?.string ?? ""
}

extension Optional where Wrapped == FHIRPrimitive<FHIRString> {
    public var string: String? { get }                  // Returns value?.string
}
```

**Example:**

```swift
let patient: ModelsR5.Patient = ...
let familyName = patient.name?.first?.family?.string   // Convenience accessor
```

#### FHIRPrimitive<FHIRDate>

```swift
extension FHIRPrimitive where PrimitiveType == FHIRDate {
    public var nsDate: Date? { get }                    // Returns try? value?.asNSDate()
}
```

**Example:**

```swift
if let birthDate = patient.birthDate?.nsDate {
    print("Born: \(birthDate)")
}
```

#### Element Extensions

```swift
extension Element {
    public func extensions(for uri: String) -> [ModelsR5.Extension]
}
```

**Example:**

```swift
let translations = element.extensions(for: "http://hl7.org/fhir/StructureDefinition/translation")
```

#### String Localization

```swift
extension String {
    public var fhir_localized: String { get }          // NSLocalizedString wrapper
}
```

**Example:**

```swift
label.text = "Loading...".fhir_localized
```

#### Patient Display Helpers

```swift
extension ModelsR5.Patient {
    var displayNameFamilyGiven: String { get }         // "Smith, John" format
    var currentAge: String { get }                     // "42 years old" format
    var genderSymbol: String { get }                   // "♂" or "♀" (iOS only)
}
```

---

## OAuth2 Types (From OAuth2 Framework)

Swift-SMART integrates with the [p2/OAuth2](https://github.com/p2/OAuth2) framework.

### OAuth2JSON

```swift
public typealias OAuth2JSON = [String: Any]
```

Used for settings dictionaries and OAuth responses.

### OAuth2Logger

```swift
public protocol OAuth2Logger {
    func debug(_ module: String, msg: String)
    func warn(_ module: String, msg: String)
    func trace(_ module: String, msg: String)
}
```

---

## FHIR Types (From ModelsR5)

Swift-SMART re-exports ModelsR5, so implementers have direct access to all FHIR R5 resources.

```swift
import SMART  // Automatically imports ModelsR5

let patient = ModelsR5.Patient(...)
let observation = ModelsR5.Observation(...)
let bundle = ModelsR5.Bundle(...)
```

### Key Resource Types

- `ModelsR5.Patient`
- `ModelsR5.Bundle`
- `ModelsR5.Observation`
- `ModelsR5.Encounter`
- `ModelsR5.Practitioner`
- All other FHIR R5 resources

---

## Complete Usage Examples

### Example 1: Standalone Launch with Patient Selection

```swift
import SMART
import UIKit

class ViewController: UIViewController {
    let client: Client

    init() {
        client = Client(
            baseURL: URL(string: "https://fhir.example.org")!,
            settings: [
                "client_id": "my-app",
                "redirect": "myapp://callback",
                "scope": "patient/*.rs offline_access openid fhirUser"
            ]
        )
        super.init(nibName: nil, bundle: nil)
    }

    func connect() {
        client.authProperties.granularity = .patientSelectNative

        client.authorize { [weak self] patient, error in
            guard let patient = patient, error == nil else {
                print("Authorization failed: \(error)")
                return
            }

            print("Authorized! Patient: \(patient.displayNameFamilyGiven)")
            self?.fetchObservations(for: patient)
        }
    }

    func fetchObservations(for patient: ModelsR5.Patient) {
        guard let patientId = patient.id?.value?.string else { return }

        let operation = DecodingFHIRRequestOperation<ModelsR5.Bundle>(
            path: "Observation?patient=\(patientId)&_count=10",
            headers: ["Accept": "application/fhir+json"]
        )

        var cancellable: AnyCancellable?
        cancellable = client.server.fhirClient.execute(operation: operation)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Search failed: \(error)")
                    }
                },
                receiveValue: { bundle in
                    print("Received \(bundle.entry?.count ?? 0) observations")
                }
            )
    }
}

// In AppDelegate
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return viewController.client.didRedirect(to: url)
}
```

---

### Example 2: EHR Launch

```swift
import SMART

class SMARTLaunchHandler {
    let client: Client

    init(baseURL: URL) {
        client = Client(
            baseURL: baseURL,
            settings: [
                "client_id": "ehr-integrated-app",
                "redirect": "myapp://callback"
            ]
        )
    }

    func handleLaunch(iss: String, launch: String) {
        // Step 1: Process EHR launch parameters
        client.handleEHRLaunch(iss: iss, launch: launch) { [weak self] error in
            guard error == nil, let self = self else {
                print("EHR launch setup failed: \(error)")
                return
            }

            // Step 2: Authorize (this will use the launch context)
            self.client.authorize { patient, error in
                guard error == nil else {
                    print("Authorization failed: \(error)")
                    return
                }

                // Step 3: Access launch context
                if let context = self.client.server.launchContext {
                    print("Patient: \(context.patient ?? "none")")
                    print("Encounter: \(context.encounter ?? "none")")
                    print("fhirUser: \(context.user?.absoluteString ?? "none")")
                    print("Need patient banner: \(context.needPatientBanner ?? false)")
                }

                // Step 4: Make FHIR API calls
                self.loadPatientData()
            }
        }
    }

    func loadPatientData() {
        guard let patientId = client.server.launchContext?.patient else { return }

        client.server.fetchPatient(id: patientId) { result in
            switch result {
            case .success(let patient):
                print("Loaded: \(patient.displayNameFamilyGiven)")
            case .failure(let error):
                print("Failed: \(error)")
            }
        }
    }
}

// Usage in AppDelegate or SceneDelegate
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }

    // Parse launch parameters from URL
    let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    guard let iss = components?.queryItems?.first(where: { $0.name == "iss" })?.value,
          let launch = components?.queryItems?.first(where: { $0.name == "launch" })?.value else {
        // Not a SMART launch, try OAuth redirect
        _ = launchHandler.client.didRedirect(to: url)
        return
    }

    launchHandler.handleLaunch(iss: iss, launch: launch)
}
```

---

### Example 3: Custom FHIR Operation

```swift
import FHIRClient
import HTTPClient
import ModelsR5

struct SearchPatientsOperation: FHIRClientOperation {
    typealias Value = ModelsR5.Bundle

    let familyName: String
    let givenName: String?
    let pageSize: Int

    var relativeUrlString: String? {
        var params = "Patient?family=\(familyName)&_count=\(pageSize)"
        if let given = givenName {
            params += "&given=\(given)"
        }
        return params
    }

    var httpHeaders: [String: String] {
        ["Accept": "application/fhir+json"]
    }

    var httpMethod: HTTPMethod {
        .get
    }

    func handle(response: FHIRClient.Response) throws -> ModelsR5.Bundle {
        try JSONDecoder().decode(ModelsR5.Bundle.self, from: response.body)
    }
}

// Usage
let operation = SearchPatientsOperation(familyName: "Smith", givenName: "John", pageSize: 50)
server.fhirClient.execute(operation: operation)
    .sink(
        receiveCompletion: { _ in },
        receiveValue: { bundle in
            print("Found \(bundle.entry?.count ?? 0) patients")
        }
    )
```

---

### Example 4: Access Token Inspection

```swift
// After successful authorization
if let accessToken = client.server.auth?.oauth?.accessToken {
    print("Access token: \(accessToken)")
    print("Token expires: \(client.server.auth?.oauth?.accessTokenExpiry)")
}

if let refreshToken = client.server.refreshToken {
    print("Refresh token available: \(refreshToken)")
}

if let idToken = client.server.idToken {
    print("ID token (OpenID Connect): \(idToken)")
}
```

---

## iOS-Specific APIs

### PatientListViewController

Native iOS patient selection UI (used when `granularity = .patientSelectNative`).

```swift
#if os(iOS)
import UIKit

open class PatientListViewController: UITableViewController {
    public var onPatientSelect: ((ModelsR5.Patient?) -> Void)?

    public init(list: PatientList, server: Server)
}

// Direct usage (if not using auto-launched patient selection)
let patientList = PatientListAll()
let viewController = PatientListViewController(list: patientList, server: client.server)
viewController.onPatientSelect = { patient in
    print("User selected: \(patient?.displayNameFamilyGiven ?? "none")")
}
present(UINavigationController(rootViewController: viewController), animated: true)
#endif
```

---

## Error Handling

### SMARTError

```swift
public enum SMARTError: LocalizedError {
    case invalidIssuer(String)
    case missingAuthorization
    case configuration(String)
    case generic(String)
}
```

### OAuth2Error (from OAuth2 framework)

The OAuth2 framework provides its own error types for auth failures.

### FHIRClient.Error (from FHIRClient module)

```swift
public enum FHIRClient.Error: Swift.Error {
    case internalError(String)
    case inconsistentResponse
    case decoding(Swift.Error)
    case unknown(Swift.Error)
    case http(FHIRClientHttpError)
}
```

---

## Info.plist Requirements

### URL Scheme Registration

Add your redirect URI scheme to `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myapp</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.example.myapp</string>
    </dict>
</array>
```

### Optional: Whitelist EHR Domains (iOS 9+)

If using embedded webview:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>fhir.example.org</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## Module Imports

```swift
import SMART                    // Main module (exports ModelsR5, OAuth2)
import ModelsR5                 // FHIR R5 resource types (auto-imported by SMART)
import OAuth2                   // OAuth2 framework (auto-imported by SMART)

// Optional advanced usage
import FHIRClient              // For custom FHIRClientOperation
import HTTPClient              // For custom Interceptor
```

---

## Not Exposed (Internal Implementation)

The following are internal and NOT part of the public API:

- `OAuth2BearerInterceptor` - Internal interceptor
- `PKCE` - Internal PKCE generation (automatic)
- `SMARTError` - Internal (but exposed via Error protocol)
- `Threading.swift` utilities
- `DecodingFHIRRequestOperation`, `RawFHIRRequestOperation` - Internal operation helpers
- `Auth` class - Internal (accessed via `Server.auth`)

---

## Migration Guide (from Swift-SMART 1.0)

| Swift-SMART 1.0              | Swift-SMART 2.0 (R5)                  | Notes                       |
| ---------------------------- | ------------------------------------- | --------------------------- |
| `Patient.read(id, server:)`  | `server.fetchPatient(id:completion:)` | Static methods removed      |
| `FHIRSearch`                 | `PatientListQuery`                    | New query builder           |
| `FHIRError`                  | `SMARTError` + other errors           | Different error types       |
| `FHIRServerJSONResponse`     | `FHIRClient.Response`                 | New response type           |
| `.string` on FHIRPrimitive   | `.string` (via extension)             | Compatibility maintained    |
| `.nsDate` on date primitives | `.nsDate` (via extension)             | Compatibility maintained    |
| `extension_fhir`             | `` `extension` ``                     | ModelsR5 uses Swift keyword |
| `.extensions(forURI:)`       | `.extensions(for:)`                   | Renamed parameter           |

---

## Quick Start Checklist

1. **Add Dependency**

   ```swift
   // Package.swift
   dependencies: [
       .package(url: "https://github.com/your-org/Swift-SMART", from: "3.0.0")
   ]
   ```

2. **Register redirect URI in Info.plist**

3. **Initialize Client**

   ```swift
   let client = Client(baseURL: ..., settings: ...)
   ```

4. **Choose Launch Type**

   - EHR Launch: `client.handleEHRLaunch()` then `client.authorize()`
   - Standalone: `client.authorize()`

5. **Handle OAuth Redirect**

   ```swift
   func application(..., open url: URL, ...) -> Bool {
       return client.didRedirect(to: url)
   }
   ```

6. **Access FHIR API**
   ```swift
   client.server.fhirClient.execute(operation: ...)
   ```

---

## Support & Documentation

- **SMART App Launch Spec:** https://hl7.org/fhir/smart-app-launch/
- **FHIR R5 Spec:** https://hl7.org/fhir/R5/
- **OAuth2 Framework:** https://github.com/p2/OAuth2
- **Apple FHIRModels:** https://github.com/apple/FHIRModels

---

## Summary

### Core Public API (5 classes)

1. **`Client`** - Main entry point for authorization and API access
2. **`Server`** - FHIR server connection, discovery, token management
3. **`PatientList`** - Paginated patient search and display
4. **`PatientListQuery`** - Search query configuration
5. **`PatientListViewController`** (iOS only) - Native patient selection UI

### Supporting Types (5 structs/enums)

1. **`SMARTAuthProperties`** - Authorization behavior config
2. **`SMARTAuthGranularity`** - Authorization granularity options
3. **`LaunchContext`** - Parsed launch context from token response
4. **`SMARTConfiguration`** - `.well-known/smart-configuration` data
5. **`PatientListOrder`** - Patient sorting options

### ModelsR5 Extensions (4 categories)

1. **FHIRPrimitive accessors** - `.string`, `.nsDate`, `.int32`
2. **Element extensions** - `.extensions(for:)`
3. **String helpers** - `.fhir_localized`
4. **Patient display** - `.displayNameFamilyGiven`, `.currentAge`, `.genderSymbol`

### Dependencies Exposed

1. **OAuth2** framework (auth flows, token management)
2. **ModelsR5** (all FHIR R5 resources)
3. **FHIRClient** (for custom operations)
4. **HTTPClient** (for custom interceptors)

The public API is designed for simplicity while maintaining flexibility for advanced use cases.
