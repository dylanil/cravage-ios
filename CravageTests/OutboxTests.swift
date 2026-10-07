import XCTest
@testable import Cravage

/// The per-connection send queue NetworkTransport uses (review findings 4 and 6).
@MainActor
final class OutboxTests: XCTestCase {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Data] = []
        var failAfter: Int?
        var blockForever = false
        func send(_ data: Data) async throws {
            if blockForever { try await Task.sleep(for: .seconds(60)) }
            try lock.withLock {
                if let limit = failAfter, stored.count >= limit { throw URLError(.networkConnectionLost) }
                stored.append(data)
            }
        }
        var sent: [Data] { lock.withLock { stored } }
    }

    func testSendsInOrder() async {
        let recorder = Recorder()
        let outbox = Outbox(send: recorder.send)
        let items = (0..<50).map { Data([UInt8($0)]) }
        for item in items { XCTAssertTrue(outbox.enqueue(item)) }
        await outbox.close(drainMs: 5_000)
        XCTAssertEqual(recorder.sent, items)
    }

    func testClosingDrainsWhatIsAlreadyQueuedThenRefusesMore() async {
        let recorder = Recorder()
        let outbox = Outbox(send: recorder.send)
        XCTAssertTrue(outbox.enqueue(Data("abort".utf8)))
        await outbox.close(drainMs: 5_000)
        XCTAssertEqual(recorder.sent, [Data("abort".utf8)], "the last message goes out before the connection closes")
        XCTAssertFalse(outbox.enqueue(Data("late".utf8)))
    }

    func testAFullQueueRefusesInsteadOfDroppingOldMessages() async {
        let recorder = Recorder()
        recorder.blockForever = true
        let outbox = Outbox(send: recorder.send)
        var accepted = 0
        for index in 0..<(Outbox.capacity + 10) where outbox.enqueue(Data([UInt8(index % 256)])) { accepted += 1 }
        XCTAssertLessThanOrEqual(accepted, Outbox.capacity + 1, "one may already be in flight")
        XCTAssertGreaterThanOrEqual(accepted, Outbox.capacity)
        await outbox.close(drainMs: 50)
    }

    func testASendFailureStopsTheQueue() async {
        let recorder = Recorder()
        recorder.failAfter = 2
        let outbox = Outbox(send: recorder.send)
        for index in 0..<5 { _ = outbox.enqueue(Data([UInt8(index)])) }
        await outbox.close(drainMs: 5_000)
        XCTAssertEqual(recorder.sent.count, 2)
        XCTAssertTrue(outbox.failed)
        XCTAssertFalse(outbox.enqueue(Data([9])))
    }

    func testDrainGivesUpAfterTheTimeLimit() async {
        let recorder = Recorder()
        recorder.blockForever = true
        let outbox = Outbox(send: recorder.send)
        _ = outbox.enqueue(Data([1]))
        let started = ContinuousClock.now
        await outbox.close(drainMs: 100)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }
}
