import Foundation

final class SleepRecorder {
    private(set) var recordedDelays: [TimeInterval] = []

    func handler() -> (TimeInterval) async throws -> Void {
        { [weak self] delay in
            self?.recordedDelays.append(delay)
        }
    }
}


