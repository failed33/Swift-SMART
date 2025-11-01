# Testing Strategy Update - Helpers Directory Exclusion

## Summary of Changes

The testing strategy has been updated to reflect the project's restructured layout where `Sources/helpers/` contains presentation/UI helper components that are **excluded from the testing strategy**.

## Excluded Components

The following components in `Sources/helpers/` are **NOT included in unit or integration tests**:

### Helper Classes (Presentation Layer)

- **`PatientList.swift`** - Patient list UI management and callbacks
- **`PatientListQuery.swift`** - Query building for patient list searches
- **`PatientListOrder.swift`** - Patient sorting logic and display formatting

### Platform-Specific UI Helpers

- **`iOS/Auth+iOS.swift`** - iOS-specific authentication UI flows
- **`iOS/PatientList+iOS.swift`** - iOS-specific patient list UI
- **`macOS/Auth+macOS.swift`** - macOS-specific authentication UI flows

## Rationale

These components are presentation layer helpers that:

1. Handle UI-specific logic and callbacks
2. Contain platform-specific code that requires manual testing
3. Will be validated through integration testing and manual QA rather than automated unit tests

## Updated Testing Focus

### Priority 1 - Core Logic (100% Coverage Required)

1. **PKCE generation** (`Sources/Client/PKCE.swift`)
2. **SMART Configuration parsing** (`Sources/Client/SMARTConfiguration.swift`)
3. **Launch Context parsing** (`Sources/Client/LaunchContext.swift`)
4. **Scope normalization** (`Sources/Client/Auth.swift`)
5. **ModelsR5 extensions** (`Sources/Client/ModelsR5+SMART.swift`)

### Priority 2 - Integration Tests

1. **Server discovery** with mock HTTP
2. **OAuth2BearerInterceptor** for token injection
3. **FHIR Operations** (raw and decoding)
4. **Client API methods** (getJSON, getData)

### Priority 3 - E2E & Performance

1. **E2E tests** against local SMART launcher (`http://localhost:8080/...`)
2. **Performance benchmarks** for critical paths
3. **Cross-platform validation** (iOS/macOS)

## Documentation Updates

The following sections in `TESTING_STRATEGY.md` have been updated:

1. **New Section**: "Testing Scope & Exclusions" - Lists all excluded components
2. **Unit Tests Table**: Removed PatientListQuery and PatientListOrder entries
3. **Integration Tests Table**: Removed PatientList entry
4. **Execution Plan**: Removed references to helpers directory tests
5. **Priority Summary**: Removed PatientList from Priority 2

## Coverage Goals (Updated)

| Category          | Target   | Notes                                |
| ----------------- | -------- | ------------------------------------ |
| Core Client Logic | 100%     | PKCE, Config, Auth, LaunchContext    |
| HTTP/FHIR Clients | 90%+     | HTTPClient, FHIRClient, Interceptors |
| Helpers Directory | 0%       | **Excluded from automated testing**  |
| **Overall**       | **80%+** | Excluding helpers directory          |

## Implementation Impact

### Tests Removed from Plan

- ❌ `Tests/Unit/PatientListQueryTests.swift`
- ❌ `Tests/Unit/PatientListOrderTests.swift`
- ❌ `Tests/Integration/PatientListTests.swift`

### Tests Remaining (Core Focus)

- ✅ `Tests/Unit/PKCETests.swift`
- ✅ `Tests/Unit/SMARTConfigurationTests.swift`
- ✅ `Tests/Unit/LaunchContextTests.swift`
- ✅ `Tests/Unit/AuthTests.swift`
- ✅ `Tests/Unit/ModelsR5ExtensionTests.swift`
- ✅ `Tests/Integration/ServerDiscoveryTests.swift`
- ✅ `Tests/Integration/OAuth2InterceptorTests.swift`
- ✅ `Tests/Integration/FHIROperationsTests.swift`
- ✅ `Tests/E2E/LocalSMARTTests.swift`
- ✅ `Tests/E2E/PublicResourceTests.swift`
- ✅ `Tests/E2E/OAuthFlowManualTests.swift`

## Next Steps

Ready to begin implementation with:

1. **Phase 1**: Set up test infrastructure (Package.swift, directories, mocks)
2. **Phase 2**: Implement Priority 1 unit tests (PKCE, Config, Launch Context, Auth)
3. **Phase 3**: Implement integration tests with mock HTTP
4. **Phase 4**: Implement E2E tests against local SMART server
5. **Phase 5**: Performance tests and CI/CD pipeline

The updated strategy maintains comprehensive coverage of core business logic while acknowledging that UI/presentation helpers require different validation approaches.
