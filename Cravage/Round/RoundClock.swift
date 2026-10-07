import Foundation

/// Monotonic milliseconds for RoundEngine deadlines, and a way to wait until one.
@MainActor
protocol RoundClock: AnyObject {
    func nowMs() -> UInt64
    func sleep(untilMs: UInt64) async throws
}

@MainActor
final class LiveClock: RoundClock {
    private let origin = ContinuousClock.now

    func nowMs() -> UInt64 {
        let elapsed = ContinuousClock.now - origin
        let (seconds, attoseconds) = elapsed.components
        return UInt64(max(seconds, 0)) * 1_000 + UInt64(max(attoseconds, 0) / 1_000_000_000_000_000)
    }

    func sleep(untilMs: UInt64) async throws {
        let now = nowMs()
        guard untilMs > now else { return }
        try await Task.sleep(for: .milliseconds(Int64(min(untilMs - now, UInt64(Int64.max)))))
    }
}
