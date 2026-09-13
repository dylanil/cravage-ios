import XCTest
import Foundation
@testable import CravageCore

/// Stream framing used by the app's NetworkTransport over TCP, and the per-connection receive loop.
/// The loop is the real code the transport runs; these tests drive it with scripted byte sources,
/// including ones that throw mid-frame (retro gate: failure-path cleanup with a throwing stream).
final class FramingTests: XCTestCase {

    /// A byte source that serves `bytes` in whatever chunks are asked for, then throws `end`.
    final class ScriptedSource: @unchecked Sendable {
        var bytes: [UInt8]
        let end: Error
        var reads: [Int] = []
        init(_ bytes: [UInt8], end: Error = Ended()) { self.bytes = bytes; self.end = end }
        struct Ended: Error, Equatable {}
        func receiveExactly(_ count: Int) async throws -> Data {
            reads.append(count)
            guard bytes.count >= count else { bytes = []; throw end }
            let chunk = Data(bytes.prefix(count))
            bytes.removeFirst(count)
            return chunk
        }
    }

    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Data] = []
        func add(_ data: Data) { lock.lock(); stored.append(data); lock.unlock() }
        var items: [Data] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    func testEncodeIsBigEndianLengthThenPayload() {
        let frame = Framing.encode(Data("hi".utf8))
        XCTAssertEqual(Array(frame), [0, 0, 0, 2, UInt8(ascii: "h"), UInt8(ascii: "i")])
    }

    func testFramesRoundTripAcrossOneStream() async throws {
        let payloads = [Data("one".utf8), Data(repeating: 7, count: MessageDomain.maxEnvelopeBytes), Data("three".utf8)]
        let source = ScriptedSource(Array(payloads.map(Framing.encode).reduce(Data(), +)))
        for payload in payloads {
            let frame = try await Framing.readFrame(receiveExactly: source.receiveExactly)
            XCTAssertEqual(frame, payload)
        }
    }

    func testOversizedLengthIsRejectedBeforeTheBodyIsRead() async {
        let length = UInt32(MessageDomain.maxEnvelopeBytes + 1)
        let source = ScriptedSource([UInt8(length >> 24), UInt8((length >> 16) & 0xff), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)])
        do {
            _ = try await Framing.readFrame(receiveExactly: source.receiveExactly)
            XCTFail("accepted an oversized frame")
        } catch {
            XCTAssertEqual(error as? Framing.FrameError, .oversized)
        }
        XCTAssertEqual(source.reads, [4], "only the header was read")
    }

    func testEmptyFrameIsRejected() async {
        let source = ScriptedSource([0, 0, 0, 0])
        do {
            _ = try await Framing.readFrame(receiveExactly: source.receiveExactly)
            XCTFail("accepted an empty frame")
        } catch {
            XCTAssertEqual(error as? Framing.FrameError, .empty)
        }
    }

    func testPumpDeliversCompleteFramesThenReportsAThrownFailureWithoutThrowing() async {
        let good = Framing.encode(Data("first".utf8)) + Framing.encode(Data("second".utf8))
        let partial = Framing.encode(Data("never delivered".utf8)).prefix(9)
        let source = ScriptedSource(Array(good + partial))
        let delivered = Collector()
        let end = await Framing.pump(receiveExactly: source.receiveExactly) { delivered.add($0) }
        XCTAssertEqual(delivered.items, [Data("first".utf8), Data("second".utf8)])
        XCTAssertEqual(end, .failed, "a throwing stream ends the loop; the caller's cleanup then runs")
    }

    func testPumpStopsOnAProtocolViolationAndSaysSo() async {
        let source = ScriptedSource(Array(Framing.encode(Data("ok".utf8))) + [0xff, 0xff, 0xff, 0xff])
        let delivered = Collector()
        let end = await Framing.pump(receiveExactly: source.receiveExactly) { delivered.add($0) }
        XCTAssertEqual(delivered.items.count, 1)
        XCTAssertEqual(end, .rejected(.oversized))
    }

    func testPumpHonoursCancellation() async {
        let source = ScriptedSource(Array(Framing.encode(Data("x".utf8))))
        let task = Task { () -> Framing.ConnectionEnd in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Framing.pump(receiveExactly: source.receiveExactly) { _ in }
        }
        let end = await task.value
        XCTAssertEqual(end, .cancelled)
    }
}
