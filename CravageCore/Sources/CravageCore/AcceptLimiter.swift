// AcceptLimiter: token-bucket limit on how fast a host accepts inbound connections (docs/SPEC.md
// section 2, required independently of signatures). Each accept costs the host a signed welcome, so
// a nearby stranger opening connections in a loop must not be able to spend the host's time.

public struct AcceptLimiter: Sendable {
    public let burst: Int
    public let refillEveryMs: UInt64
    private var tokens: Int
    private var lastRefillMs: UInt64?

    /// Defaults: a whole eight-person room can arrive at once with retries; after that one new
    /// connection per half second.
    public init(burst: Int = 12, refillEveryMs: UInt64 = 500) {
        self.burst = burst
        self.refillEveryMs = refillEveryMs
        self.tokens = burst
    }

    public mutating func allow(nowMs: UInt64) -> Bool {
        if let last = lastRefillMs {
            if nowMs > last {
                let earned = (nowMs - last) / refillEveryMs
                if earned > 0 {
                    tokens = min(burst, tokens + Int(min(earned, UInt64(burst))))
                    lastRefillMs = last + earned * refillEveryMs
                }
            }
        } else {
            lastRefillMs = nowMs
        }
        guard tokens > 0 else { return false }
        tokens -= 1
        return true
    }
}
