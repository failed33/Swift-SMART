import Foundation

public struct RetryDirective {
    public enum Reason {
        case retryAfter
        case transient
    }

    public let delay: TimeInterval
    public let reason: Reason
}

public struct RetryPolicy {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var maxBackoff: TimeInterval?
    public var jitter: ClosedRange<Double>?
    public var allowedMethods: Set<String>
    public var retryAfterRetries: Int
    private let randomGenerator: (ClosedRange<Double>) -> Double

    public init(
        maxRetries: Int = 0,
        baseDelay: TimeInterval = 0.5,
        maxBackoff: TimeInterval? = nil,
        jitter: ClosedRange<Double>? = nil,
        allowedMethods: Set<String> = ["GET", "HEAD"],
        retryAfterRetries: Int = 1,
        randomGenerator: @escaping (ClosedRange<Double>) -> Double = { range in
            Double.random(in: range)
        }
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxBackoff = maxBackoff
        self.jitter = jitter
        self.allowedMethods = allowedMethods
        self.retryAfterRetries = retryAfterRetries
        self.randomGenerator = randomGenerator
    }

    public func directiveForResponse(
        statusCode: Int,
        method: String?,
        retryAfterHeader: String?,
        attempt: Int
    ) -> RetryDirective? {
        guard allows(method: method) else { return nil }

        if let retryAfterHeader,
           let delay = retryAfterDelay(from: retryAfterHeader),
           attempt < retryAfterRetries {
            return RetryDirective(delay: max(delay, 0), reason: .retryAfter)
        }

        guard maxRetries > 0, attempt < maxRetries else { return nil }
        guard isTransientStatus(statusCode) else { return nil }

        return RetryDirective(delay: backoffDelay(forAttempt: attempt), reason: .transient)
    }

    public func directiveForError(_ error: URLError, method: String?, attempt: Int) -> RetryDirective? {
        guard allows(method: method) else { return nil }
        guard maxRetries > 0, attempt < maxRetries else { return nil }
        guard isTransientURLError(error) else { return nil }

        return RetryDirective(delay: backoffDelay(forAttempt: attempt), reason: .transient)
    }

    private func allows(method: String?) -> Bool {
        guard let method else { return false }
        return allowedMethods.contains(method.uppercased())
    }

    private func retryAfterDelay(from header: String) -> TimeInterval? {
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        if let date = HTTPDateParser.parse(header) {
            return date.timeIntervalSinceNow
        }
        return nil
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let factor = pow(2.0, Double(attempt))
        var delay = baseDelay * factor
        if let maxBackoff {
            delay = min(delay, maxBackoff)
        }

        if let jitter {
            let randomFactor = randomGenerator(jitter)
            delay *= 1.0 + randomFactor
        }

        return delay
    }

    private func isTransientStatus(_ status: Int) -> Bool {
        switch status {
        case 408, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private func isTransientURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .backgroundSessionWasDisconnected,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}

enum HTTPDateParser {
    static func parse(_ value: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static var formatters: [DateFormatter] = {
        let locales = Locale(identifier: "en_US_POSIX")

        let rfc1123 = DateFormatter()
        rfc1123.locale = locales
        rfc1123.timeZone = TimeZone(secondsFromGMT: 0)
        rfc1123.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        let rfc850 = DateFormatter()
        rfc850.locale = locales
        rfc850.timeZone = TimeZone(secondsFromGMT: 0)
        rfc850.dateFormat = "EEEE',' dd-MMM-yy HH':'mm':'ss z"

        let asctime = DateFormatter()
        asctime.locale = locales
        asctime.timeZone = TimeZone(secondsFromGMT: 0)
        asctime.dateFormat = "EEE MMM  d HH':'mm':'ss yyyy"

        return [rfc1123, rfc850, asctime]
    }()
}

