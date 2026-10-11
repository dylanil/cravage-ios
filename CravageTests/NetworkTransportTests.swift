import XCTest
@testable import Cravage
import CravageCore

/// Control the actual TCP byte boundary while retaining NetworkTransport's framing, outbox,
/// receive loop and close callbacks. No Network framework substitute is compiled into the app.
private actor HeldTCP {
    let sending = XCTestExpectation(description: "send started")
    let reading = XCTestExpectation(description: "read started")
    let sendCancelled = XCTestExpectation(description: "send cancelled during close")
    private var writer: CheckedContinuation<Void, Never>?
    private var reader: CheckedContinuation<Data, Error>?
    private var released = false
    private var readFailed = false

    func send(_ data: Data) async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sending.fulfill()
                if released { continuation.resume() } else { writer = continuation }
            }
        } onCancel: {
            sendCancelled.fulfill()
        }
    }

    func receiveExactly(_ count: Int) async throws -> Data {
        reading.fulfill()
        if readFailed { throw URLError(.networkConnectionLost) }
        return try await withCheckedThrowingContinuation { reader = $0 }
    }

    func releaseSend() {
        released = true
        writer?.resume()
        writer = nil
    }

    func failRead() {
        readFailed = true
        reader?.resume(throwing: URLError(.networkConnectionLost))
        reader = nil
    }
}

/// Serves the given bytes to `receive(exactly:)` calls, then fails as a lost connection would.
private actor ScriptedReader {
    private var bytes: Data
    init(frames: [Data]) { bytes = frames.reduce(Data()) { $0 + (try! Framing.encode($1)) } }

    func receiveExactly(_ count: Int) async throws -> Data {
        guard bytes.count >= count else { throw URLError(.networkConnectionLost) }
        let chunk = bytes.prefix(count)
        bytes.removeFirst(count)
        return Data(chunk)
    }
}

@MainActor
final class NetworkTransportTests: XCTestCase {
    private func settle(until done: @MainActor () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Hypothesis 2 of the 2026-10-09 device report: one send never returns, so nothing fails and
    /// nothing more goes out. The report must show the send in progress and what is queued behind it.
    func testALinkReportShowsASendThatNeverFinishes() async {
        let transport = NetworkTransport()
        let tcp = HeldTCP()
        transport.open(as: .host, send: tcp.send, receiveExactly: tcp.receiveExactly)
        for byte in UInt8(1)...3 { transport.send(Data([byte]), to: .host) }
        await fulfillment(of: [tcp.sending], timeout: 2)

        let stuck = transport.linkReports
        XCTAssertEqual(stuck.count, 1)
        XCTAssertEqual(stuck.first?.toHost, true)
        XCTAssertEqual(stuck.first?.end, .open)
        XCTAssertEqual(stuck.first?.framesSent, 0)
        XCTAssertEqual(stuck.first?.waitingToSend, 3, "the send in progress and the two behind it")
        XCTAssertNotNil(stuck.first?.secondsSending, "a send is in progress")

        await tcp.releaseSend()
        await settle { transport.linkReports.first?.framesSent == 3 }
        let flowing = transport.linkReports.first
        XCTAssertEqual(flowing?.framesSent, 3)
        XCTAssertEqual(flowing?.waitingToSend, 0)
        XCTAssertNil(flowing?.secondsSending)
        transport.stopAll()
        await tcp.failRead()
    }

    /// Hypotheses 1 and 3: the link goes quiet, or the host stops reading. The report counts what
    /// arrived and says how the connection ended, and keeps an ended link until `stopAll`.
    func testALinkReportCountsWhatArrivedAndHowItEnded() async {
        let transport = NetworkTransport()
        let reader = ScriptedReader(frames: [Data([7]), Data([8])])
        let ended = expectation(description: "connection lost")
        transport.onEvent = { if case .peerDisconnected = $0 { ended.fulfill() } }
        transport.open(as: PeerID(1), send: { _ in }, receiveExactly: reader.receiveExactly)
        await fulfillment(of: [ended], timeout: 2)

        let report = transport.linkReports
        XCTAssertEqual(report.count, 1, "an ended link is still reported")
        XCTAssertEqual(report.first?.toHost, false)
        XCTAssertEqual(report.first?.end, .lost)
        XCTAssertEqual(report.first?.framesReceived, 2)
        XCTAssertEqual(report.first?.secondsSinceLastReceived, 0)

        transport.stopAll()
        XCTAssertTrue(transport.linkReports.isEmpty, "a new room starts a new report")
    }

    func testALinkReportSaysWhoEndedIt() async {
        let transport = NetworkTransport()
        let failing = HeldTCP()
        transport.open(as: PeerID(1), send: { _ in throw URLError(.networkConnectionLost) },
                       receiveExactly: failing.receiveExactly)
        let closed = HeldTCP()
        transport.open(as: PeerID(2), send: closed.send, receiveExactly: closed.receiveExactly)
        let silent = HeldTCP()
        transport.open(as: PeerID(3), send: silent.send, receiveExactly: silent.receiveExactly)
        transport.send(Data([1]), to: PeerID(1))
        transport.disconnect(PeerID(2))
        await settle { transport.linkReports.first?.end == .sendFailed && transport.linkReports[1].end == .closedHere }

        XCTAssertEqual(transport.linkReports.map(\.end), [.sendFailed, .closedHere, .open],
                       "in the order the links opened")
        XCTAssertEqual(transport.linkReports[0].waitingToSend, 0, "the failed send is not still waiting")
        XCTAssertNil(transport.linkReports[0].secondsSending)
        XCTAssertNil(transport.linkReports[2].secondsSinceLastReceived, "nothing ever arrived")
        transport.stopAll()
        for tcp in [failing, closed, silent] { await tcp.failRead() }
    }
    func testOldExplicitDisconnectCannotReportFailureAfterStopAndRejoin() async {
        for (stop, replace) in [(true, false), (true, true), (false, true)] {
            let transport = NetworkTransport()
            let old = HeldTCP()
            let link = transport.open(as: .host, send: old.send, receiveExactly: old.receiveExactly)
            transport.send(Data([1]), to: .host)
            await fulfillment(of: [old.sending, old.reading], timeout: 2)
            transport.disconnect(.host)
            if stop { transport.stopAll() }
            let replacement = HeldTCP()
            if replace { transport.open(as: .host, send: replacement.send, receiveExactly: replacement.receiveExactly) }
            let stale = expectation(description: "old close reported to new room")
            stale.isInverted = true
            transport.onEvent = { if case .peerDisconnected = $0 { stale.fulfill() } }
            await old.releaseSend()
            await link.waitUntilClosed()
            await old.failRead()
            await fulfillment(of: [stale], timeout: 0.1)
            transport.onEvent = nil
            transport.stopAll()
            await replacement.failRead()
        }
    }

    func testOldReceiveFailureCannotReportFailureAfterStopAndRejoin() async {
        for (stop, replace) in [(true, false), (true, true), (false, true)] {
            let transport = NetworkTransport()
            let old = HeldTCP()
            let link = transport.open(as: .host, send: old.send, receiveExactly: old.receiveExactly)
            transport.send(Data([1]), to: .host)
            await fulfillment(of: [old.sending, old.reading], timeout: 2)
            await old.failRead()
            // The receive loop has removed the old link and is awaiting the blocked outbox close.
            await fulfillment(of: [old.sendCancelled], timeout: 2)
            if stop { transport.stopAll() }
            let replacement = HeldTCP()
            if replace { transport.open(as: .host, send: replacement.send, receiveExactly: replacement.receiveExactly) }
            let stale = expectation(description: "old receive failure reported to new room")
            stale.isInverted = true
            transport.onEvent = { if case .peerDisconnected = $0 { stale.fulfill() } }
            await old.releaseSend()
            await link.waitUntilClosed()
            await fulfillment(of: [stale], timeout: 0.1)
            transport.onEvent = nil
            transport.stopAll()
            await replacement.failRead()
        }
    }

    func testCurrentConnectionFailureIsStillReportedExactlyOnce() async {
        let transport = NetworkTransport()
        let tcp = HeldTCP()
        transport.open(as: .host, send: tcp.send, receiveExactly: tcp.receiveExactly)
        let disconnected = expectation(description: "current connection failure")
        disconnected.assertForOverFulfill = true
        transport.onEvent = { if case .peerDisconnected(.host) = $0 { disconnected.fulfill() } }
        await fulfillment(of: [tcp.reading], timeout: 2)
        await tcp.failRead()
        await fulfillment(of: [disconnected], timeout: 2)
        transport.stopAll()
    }

    func testMissingEndpointFailureCannotEscapeLeaveOrReplacement() async {
        for replace in [false, true] {
            let transport = NetworkTransport()
            let stale = expectation(description: "old missing endpoint reported after leave or replacement")
            stale.isInverted = true
            transport.onEvent = { if case .peerDisconnected = $0 { stale.fulfill() } }
            transport.connect(to: "no longer advertised")
            let replacement = HeldTCP()
            if replace {
                transport.open(as: .host, send: replacement.send, receiveExactly: replacement.receiveExactly)
            } else {
                transport.stopAll()
            }
            await fulfillment(of: [stale], timeout: 0.1)
            transport.onEvent = nil
            transport.stopAll()
            await replacement.failRead()
        }
    }

    /// Device report 2026-10-04: a joiner's phone stopped receiving the others' room-code checks and
    /// later said it had lost the host. A send that fails must end the connection at once and say
    /// so, not leave a link that looks open while everything queued for it is thrown away.
    func testAFailedSendEndsTheConnectionAtOnce() async {
        let transport = NetworkTransport()
        let reported = expectation(description: "the failed send is reported as a disconnect")
        reported.assertForOverFulfill = true
        transport.onEvent = { event in
            if case .peerDisconnected(.host) = event { reported.fulfill() }
        }
        transport.open(as: .host, send: { _ in throw URLError(.networkConnectionLost) },
                       receiveExactly: { _ in try await Task.sleep(for: .seconds(60)); return Data() })
        transport.send(Data([1]), to: .host)
        await fulfillment(of: [reported], timeout: 2)
        // Exactly once: a later send, and the receive loop ending, must not report it again.
        transport.send(Data([2]), to: .host)
        let again = expectation(description: "reported a second time")
        again.isInverted = true
        transport.onEvent = { if case .peerDisconnected(.host) = $0 { again.fulfill() } }
        await fulfillment(of: [again], timeout: 0.5)
        XCTAssertEqual(transport.sendFailures, 1, "counted for diagnostics")
        transport.stopAll()
    }
}
