import Foundation

#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

enum ExternalLoginDriver {

    private static let recorderQueue = DispatchQueue(label: "ExternalLoginDriver.recorder")
    private static var recordedAuthorizeURL: URL?

    static func open(_ url: URL) throws {
        recordAuthorizeURL(url)
        if let automationEndpoint = automationEndpoint() {
            try notifyAutomation(endpoint: automationEndpoint, authorizeURL: url)
        } else {
            openInDefaultBrowser(url)
        }
    }

    private static func automationEndpoint() -> URL? {
        guard
            let value = ProcessInfo.processInfo.environment["SMART_AUTOMATION_ENDPOINT"],
            let url = URL(string: value)
        else {
            return nil
        }
        return url
    }

    private static func notifyAutomation(endpoint: URL, authorizeURL: URL) throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["authorize_url": authorizeURL.absoluteString]
        )

        let semaphore = DispatchSemaphore(value: 0)
        var capturedError: Error?

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                capturedError = error
            } else if let http = response as? HTTPURLResponse,
                http.statusCode >= 300
            {
                capturedError = NSError(
                    domain: "ExternalLoginDriver",
                    code: http.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Automation endpoint returned status \(http.statusCode)"
                    ]
                )
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)

        if let error = capturedError {
            throw error
        }
    }

    private static func recordAuthorizeURL(_ url: URL) {
        recorderQueue.sync {
            recordedAuthorizeURL = url
        }
    }

    static func takeRecordedAuthorizeURL() -> URL? {
        recorderQueue.sync {
            defer { recordedAuthorizeURL = nil }
            return recordedAuthorizeURL
        }
    }

    private static func openInDefaultBrowser(_ url: URL) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        #else
            print("Open the following URL to continue authentication: \(url.absoluteString)")
        #endif
    }
}
