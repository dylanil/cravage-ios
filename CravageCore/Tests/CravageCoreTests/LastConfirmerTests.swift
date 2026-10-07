import XCTest
@testable import CravageCore

/// Device report 2026-10-04: the joiner that confirmed last saw only its own check and then lost
/// the host. The engine was ruled out here (the cause was the transport's outbox, see
/// NetworkTransportTests.testAFailedSendEndsTheConnectionAtOnce); this keeps it ruled out.
final class LastConfirmerTests: XCTestCase {
    func testTheLastJoinerToConfirmSeesEveryoneAndStaysConnected() {
        for last in 1...2 {
            let bus = StarBus.locked(nodes: 3)
            let others = (0..<3).filter { $0 != last }
            bus.confirm(others)
            bus.advance(ms: 20_000)            // people take a while to compare codes
            XCTAssertEqual(bus.engines[last].confirmedLetters.count, 2, "last=\(last) sees the others before tapping")
            bus.confirm([last])
            XCTAssertTrue(bus.connected.contains(last), "last=\(last) still connected")
            XCTAssertEqual(bus.engines[last].phase, .keyExchange, "last=\(last)")
            XCTAssertEqual(bus.engines[last].confirmedLetters.count, 3)
        }
    }
}
