import Foundation

#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif

enum ExternalLoginDriver {

    private actor Recorder {
        var authorizeURL: URL?

        func record(_ url: URL) {
            authorizeURL = url
        }

        func take() -> URL? {
            defer { authorizeURL = nil }
            return authorizeURL
        }
    }

    private static let recorder = Recorder()
    fileprivate final class ErrorBox: @unchecked Sendable {
        private var value: Error?
        private let queue = DispatchQueue(label: "ExternalLoginDriver.error")

        func set(_ error: Error?) {
            queue.sync {
                value = error
            }
        }

        func take() -> Error? {
            queue.sync {
                defer { value = nil }
                return value
            }
        }
    }

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
        let errorBox = ErrorBox()

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                errorBox.set(error)
            } else if let http = response as? HTTPURLResponse,
                http.statusCode >= 300
            {
                let wrapped = NSError(
                    domain: "ExternalLoginDriver",
                    code: http.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Automation endpoint returned status \(http.statusCode)"
                    ]
                )
                errorBox.set(wrapped)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)

        if let error = errorBox.take() {
            throw error
        }
    }

    private static func recordAuthorizeURL(_ url: URL) {
        Task {
            await recorder.record(url)
        }
    }

    static func takeRecordedAuthorizeURL() async -> URL? {
        await recorder.take()
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
