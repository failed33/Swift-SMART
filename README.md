<p align="center"><img src="./assets/banner.png" alt=""></p>

Swift-SMART is a full client implementation of the 🔥FHIR specification for building apps that interact with healthcare data through [**SMART on FHIR**][smart].
Written in _Swift 5.0_ it is compatible with **iOS 11** and **macOS 10.13** and newer and requires Xcode 10.2 or newer.

### Versioning

Due to the complications of combining two volatile technologies, here's an overview of which version numbers use which **Swift** and **FHIR versions**.

- The [`master`](https://github.com/smart-on-fhir/Swift-SMART) branch should always compile and is on (point releases of) these main versions.
- The [`develop`](https://github.com/smart-on-fhir/Swift-SMART/tree/develop) branch should be on versions corresponding to the latest freezes and may be updated from time to time with the latest and greatest CI build.

See [tags/releases](https://github.com/smart-on-fhir/Swift-SMART/releases).

| Version   | Swift       | FHIR               | &nbsp;                        |
| --------- | ----------- | ------------------ | ----------------------------- |
| **4.2**   | 5.0 Package | `4.0.0-a53ec6ee1b` | R4                            |
| **4.1**   | 5.0         | `4.0.0-a53ec6ee1b` | R4                            |
| **4.0**   | 4.2         | `4.0.0-a53ec6ee1b` | R4                            |
| **3.2**   | 3.2         | `3.0.0.11832`      | STU 3                         |
| **3.0**   | 3.0         | `3.0.0.11832`      | STU 3                         |
| **2.9**   | 3.0         | `1.6.0.9663`       | STU 3 Ballot, Sep 2016        |
| **2.8**   | 3.0         | `1.0.2.7202`       | DSTU 2 (_+ technical errata_) |
| **2.4**   | 2.2         | `1.6.0.9663`       | STU 3 Ballot, Sep 2016        |
| **2.3**   | 2.3         | `1.0.2.7202`       | DSTU 2 (_+ technical errata_) |
| **2.2.3** | 2.2         | `1.0.2.7202`       | DSTU 2 (_+ technical errata_) |
| **2.2**   | 2.0-2.2     | `1.0.2.7202`       | DSTU 2 (_+ technical errata_) |
| **2.1**   | 2.0-2.2     | `1.0.1.7108`       | DSTU 2                        |
| **2.0**   | 2.0-2.2     | `0.5.0.5149`       | DSTU 2 Ballot, May 2015       |
| **1.0**   | 1.2         | `0.5.0.5149`       | DSTU 2 Ballot, May 2015       |
| **0.2**   | 1.1         | `0.5.0.5149`       | DSTU 2 Ballot, May 2015       |
| **0.1**   | 1.0         | `0.0.81.2382`      | DSTU 1                        |

## Resources

- [Programming Guide][wiki] with code examples
- [Technical Documentation][docs] of classes, properties and methods
- [Medication List][sample] sample app
- [SMART on FHIR][smart] API documentation

[wiki]: https://github.com/smart-on-fhir/Swift-SMART/wiki
[docs]: http://docs.smarthealthit.org/Swift-SMART/
[sample]: https://github.com/smart-on-fhir/SoF-MedList
[smart]: http://docs.smarthealthit.org

## QuickStart

See [the programming guide][wiki] for more code examples and details.

The following is the minimal setup working against our reference implementation.
It is assuming that you don't have a `client_id` and on first authentication will **register the client with our server**, then proceed to retrieve a token.
If you know your client-id you can specify it in the settings dict.
The app must also register the `redirect` URL scheme so it can be notified when authentication completes.

```swift
import SMART

// create the client
let smart = Client(
    baseURL: URL(string: "https://fhir-api-dstu2.smarthealthit.org")!,
    settings: [
        //"client_id": "my_mobile_app",       // if you have one
        "redirect": "smartapp://callback",    // must be registered
    ]
)

Task {
    do {
        guard let patient = try await smart.authorize() else {
            print("Authorization cancelled")
            return
        }

        let response = try await smart.getJSON(at: "MedicationRequest?patient=\(patient.id?.value?.string ?? "")")
        print("FHIR response status: \(response.status)")
    } catch {
        print("Authorization or fetch failed: \(error)")
    }
}

> Prefer callbacks? The legacy `authorize(callback:)` and `getJSON(..., completion:)` wrappers remain available (deprecated) and now return `Task` handles so you can cancel them.
```

For authorization to work with Safari/SFViewController, you also need to:

1. register the scheme (such as `smartapp` in the example here) in your app's `Info.plist` and
2. intercept the callback in your app delegate, like so:

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ app: UIApplication, open url: URL,
        options: [UIApplicationOpenURLOptionsKey: Any] = [:]) -> Bool {

        // "smart" is your SMART `Client` instance
        if smart.awaitingAuthCallback {
            return smart.didRedirect(to: url)
        }
        return false
    }
}
```

## Installation

The suggested approach is to add _Swift-SMART_ as a git submodule to your project.
Find detailed instructions on how this is done on the [Installation page][installation].

The framework can also be installed via _Carthage_ and is also available via _CocoaPods_ under the name [“SMART”][pod].

[installation]: https://github.com/smart-on-fhir/Swift-SMART/wiki/Installation
[pod]: https://cocoapods.org/pods/SMART

## License

This work is [Apache 2](./LICENSE.txt) licensed: [NOTICE.txt](./NOTICE.txt).
FHIR® is the registered trademark of [HL7][] and is used with the permission of HL7.

[hl7]: http://hl7.org/

### Verification & Debugging

- To verify against your test server using a non-interactive flow (client_credentials), run the live E2E test with environment variables:

```bash
SMART_BASE_URL="https://your.fhir.server/baseR5" \
SMART_CLIENT_ID="your-client-id" \
SMART_CLIENT_SECRET="your-client-secret" \
SMART_SCOPE="system/*.rs" \
SMART_TEST_QUERY_PATH="Patient?_count=1" \
swift test -c debug
```

- To run the manual OAuth checklist (authorization_code), set:

````bash

- To exercise the full Authorization Code + PKCE flow (standalone launch), export sandbox credentials and run the harness:

```bash
cp scripts/test_scripts/standalone_launch.env.example scripts/test_scripts/standalone_launch.env
# Edit values in standalone_launch.env, then invoke:
scripts/test_scripts/standalone_launch.sh
````

Set `SMART_AUTOMATION_ENDPOINT` if you have an automation worker (e.g., Playwright) listening for authorize URLs and driving the login form. Otherwise the script opens the system browser for manual interaction.

- To run the manual OAuth checklist (authorization_code), set:

```bash
RUN_MANUAL_OAUTH=1 \
SMART_LAUNCHER_URL="https://launch.smarthealthit.org" \
swift test -c debug
# After completing the documented steps, re-run with:
SMART_MANUAL_AUTH_CONFIRMED=1 RUN_MANUAL_OAUTH=1 swift test -c debug
```

- Network logging (Debug builds): inject a logging interceptor when constructing the `Server`, e.g.

```swift
let server = Server(
    baseURL: URL(string: "https://your.fhir.server/baseR5")!,
    additionalInterceptors: [LoggingInterceptor(log: .body)]
)
```

- OAuth2 internal logging: assign an `OAuth2Logger`, such as `OSLogOAuth2Logger`, after creating the server:

```swift
server.logger = OSLogOAuth2Logger()
```
