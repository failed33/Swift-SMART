//
//  OSLogOAuth2Logger.swift
//  Swift-SMART
//

import Foundation
import OAuth2
import OSLog

/// OAuth2 logger that forwards messages to `os_log`, honoring `OAuth2LogLevel`.
public final class OSLogOAuth2Logger: OAuth2Logger {
    public var level: OAuth2LogLevel
    private let logger: Logger

    public init(
        level: OAuth2LogLevel = .debug,
        subsystem: String = "SwiftSMART",
        category: String = "OAuth2"
    ) {
        self.level = level
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(
        _ atLevel: OAuth2LogLevel,
        module: String?,
        filename: String?,
        line: Int?,
        function: String?,
        msg: @autoclosure () -> String
    ) {
        guard level != .off, atLevel.rawValue >= level.rawValue else { return }

        let osLogType: OSLogType = {
            switch atLevel {
            case .trace: return .debug
            case .debug: return .info
            case .warn: return .error
            case .off: return .default
            }
        }()

        let modulePart = module ?? "OAuth2"
        let location: String
        if let filename, let line {
            location = "\(URL(fileURLWithPath: filename).lastPathComponent):\(line)"
        } else if let function {
            location = function
        } else {
            location = ""
        }

        let message = msg()
        if location.isEmpty {
            logger.log(
                level: osLogType, "[\(modulePart, privacy: .public)] \(message, privacy: .public)")
        } else {
            logger.log(
                level: osLogType,
                "[\(modulePart, privacy: .public)] \(location, privacy: .public): \(message, privacy: .public)"
            )
        }
    }
}
