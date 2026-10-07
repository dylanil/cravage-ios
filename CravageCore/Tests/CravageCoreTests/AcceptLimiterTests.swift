import XCTest
@testable import CravageCore

/// SPEC section 2: connection-rate limiting on the host's inbound accepts.
final class AcceptLimiterTests: XCTestCase {
    func testBurstIsAllowedThenRefusedUntilTokensRefill() {
        var limiter = AcceptLimiter(burst: 4, refillEveryMs: 1_000)
        for _ in 0..<4 { XCTAssertTrue(limiter.allow(nowMs: 10_000)) }
        XCTAssertFalse(limiter.allow(nowMs: 10_000))
        XCTAssertFalse(limiter.allow(nowMs: 10_999))
        XCTAssertTrue(limiter.allow(nowMs: 11_000), "one token back after a second")
        XCTAssertFalse(limiter.allow(nowMs: 11_000))
        XCTAssertTrue(limiter.allow(nowMs: 20_000))
        for _ in 0..<3 { XCTAssertTrue(limiter.allow(nowMs: 20_000)) }
        XCTAssertFalse(limiter.allow(nowMs: 20_000), "refill never exceeds the burst")
    }

    func testClockGoingBackwardsNeverGrantsTokens() {
        var limiter = AcceptLimiter(burst: 1, refillEveryMs: 1_000)
        XCTAssertTrue(limiter.allow(nowMs: 50_000))
        XCTAssertFalse(limiter.allow(nowMs: 0))
        XCTAssertFalse(limiter.allow(nowMs: 50_500))
        XCTAssertTrue(limiter.allow(nowMs: 51_000))
    }

    func testDefaultsAdmitAnHonestEightPersonRoomWithRetries() {
        var limiter = AcceptLimiter()
        var accepted = 0
        for _ in 0..<(Roster.maximumSize * 2) where limiter.allow(nowMs: 1_000) { accepted += 1 }
        XCTAssertGreaterThanOrEqual(accepted, Roster.maximumSize, "seven joiners plus retries at once")
    }
}
