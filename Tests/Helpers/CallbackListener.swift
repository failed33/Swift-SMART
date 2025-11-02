//
//  CallbackListener.swift
//  Swift-SMART Tests
//
//  Created to support RFC 8252 loopback redirects within end-to-end tests.
//

import Foundation
import Network

/// Minimal HTTP server that listens on 127.0.0.1 and captures the first redirect request.
///
/// This helper is intended for native app style OAuth testing where the authorization server
/// redirects to `http://127.0.0.1:<port>/callback?...`. The listener binds only to the loopback
/// interface, satisfies RFC 8252 requirements, and emits the captured redirect URL for tests to
/// process.
final class CallbackListener {

    enum ListenerError: Error, LocalizedError {
        case alreadyStarted
        case invalidPort(UInt16)
        case invalidRequest
        case timedOut(TimeInterval)
        case failedToStart(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .alreadyStarted:
                return "CallbackListener has already been started"
            case .invalidPort(let value):
                return "Port \(value) is not valid"
            case .invalidRequest:
                return "Received invalid redirect request"
            case .timedOut(let timeout):
                return "Timed out after waiting \(timeout) seconds for redirect"
            case .failedToStart(let error):
                return "Failed to start listener: \(error)"
            }
        }
    }

    let host: String
    let path: String

    /// The port requested by the caller. Use `0` to request an ephemeral port.
    private let requestedPort: UInt16

    /// The actual port that the listener is bound to. Valid after `start()` completes.
    private(set) var port: UInt16 = 0

    private let queue = DispatchQueue(label: "SMART.CallbackListener")
    private var listener: NWListener?
    private var redirectURL: URL?
    private var redirectSemaphore = DispatchSemaphore(value: 0)
    private var stopOnNextConnection = false

    // TODO: This should not be hardcoded to 127.0.0.1, we need to verify the loopback interface is available on the platform. We are intending to support primarily iOS and macOS. -> LOOKUP the correct redirect loopback
    init(host: String = "127.0.0.1", port: UInt16 = 0, path: String = "/callback") {
        precondition(!path.isEmpty, "Path must not be empty")
        precondition(path.starts(with: "/"), "Path must start with ‘/’")
        self.host = host
        self.path = path
        self.requestedPort = port
    }

    /// Starts the loopback listener. Must be called before `awaitRedirect`.
    func start() throws {
        try queue.sync {
            if listener != nil {
                throw ListenerError.alreadyStarted
            }

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = false
            parameters.requiredInterfaceType = .loopback

            let nwListener: NWListener
            do {
                if requestedPort == 0 {
                    nwListener = try NWListener(using: parameters)
                } else {
                    guard let nwPort = NWEndpoint.Port(rawValue: requestedPort) else {
                        throw ListenerError.invalidPort(requestedPort)
                    }
                    nwListener = try NWListener(using: parameters, on: nwPort)
                }
            } catch {
                throw ListenerError.failedToStart(error)
            }

            redirectURL = nil
            redirectSemaphore = DispatchSemaphore(value: 0)
            stopOnNextConnection = false

            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = nwListener.port?.rawValue {
                        self.port = UInt16(port)
                    }
                case .failed(let error):
                    self.queue.async {
                        self.listener?.cancel()
                        self.listener = nil
                        self.redirectSemaphore.signal()
                        self.port = 0
                        self.redirectURL = nil
                        self.stopOnNextConnection = true
                        print("CallbackListener failed with error: \(error)")
                    }
                case .cancelled:
                    self.queue.async {
                        self.listener = nil
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            nwListener.start(queue: queue)
            listener = nwListener
        }
    }

    /// Stops the listener and releases resources.
    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            stopOnNextConnection = true
            port = 0
        }
    }

    /// Waits for the redirect request, returning the captured URL.
    /// - Parameter timeout: Seconds to wait before giving up.
    func awaitRedirect(timeout: TimeInterval) throws -> URL {
        let waitResult = redirectSemaphore.wait(timeout: .now() + timeout)
        guard waitResult == .success else {
            throw ListenerError.timedOut(timeout)
        }

        return try queue.sync {
            guard let url = redirectURL else {
                throw ListenerError.invalidRequest
            }
            return url
        }
    }

    // MARK: - Connection Handling

    private func handle(connection: NWConnection) {
        if stopOnNextConnection {
            connection.cancel()
            return
        }

        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self]
            data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.finish(connection: connection, success: false)
                print("CallbackListener connection error: \(error)")
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if isComplete || buffer.containsHeaderTermination {
                self.process(buffer: buffer, connection: connection)
            } else {
                self.receive(on: connection, accumulated: buffer)
            }
        }
    }

    private func process(buffer: Data, connection: NWConnection) {
        guard let request = String(data: buffer, encoding: .utf8) else {
            finish(connection: connection, success: false)
            return
        }

        guard let requestLine = request.split(separator: "\r\n").first else {
            finish(connection: connection, success: false)
            return
        }

        let components = requestLine.split(separator: " ")
        guard components.count >= 2, components[0] == "GET" else {
            finish(connection: connection, success: false)
            return
        }

        let requestTarget = String(components[1])
        guard requestTarget.starts(with: path) || requestTarget == path else {
            finish(connection: connection, success: false)
            return
        }

        guard let base = URL(string: "http://\(host):\(port)"),
            let redirect = URL(string: requestTarget, relativeTo: base)?.absoluteURL
        else {
            finish(connection: connection, success: false)
            return
        }

        queue.async {
            self.redirectURL = redirect
            self.stopOnNextConnection = true
        }

        let responseBody = "Authorization complete. You may close this window."
        let response = """
            HTTP/1.1 200 OK
            Content-Type: text/plain; charset=utf-8
            Content-Length: \(responseBody.utf8.count)
            Connection: close

            \(responseBody)
            """

        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            })

        redirectSemaphore.signal()
    }

    private func finish(connection: NWConnection, success: Bool) {
        if !success {
            let response = """
                HTTP/1.1 400 Bad Request
                Content-Length: 0
                Connection: close

                """
            connection.send(
                content: Data(response.utf8),
                completion: .contentProcessed { _ in
                    connection.cancel()
                })
        } else {
            connection.cancel()
        }
    }
}

extension Data {
    fileprivate var containsHeaderTermination: Bool {
        return self.range(of: Data("\r\n\r\n".utf8)) != nil
    }
}
