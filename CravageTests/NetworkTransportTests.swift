import XCTest
@testable import Cravage
import CravageCore
import Network

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

/// Serves the given frames, then answers every read with nothing: a stream the other side closed.
private actor ClosingReader {
    private var bytes: Data
    init(frames: [Data]) { bytes = frames.reduce(Data()) { $0 + (try! Framing.encode($1)) } }

    func receiveExactly(_ count: Int) async throws -> Data {
        let chunk = bytes.prefix(count)
        bytes.removeFirst(chunk.count)
        return Data(chunk)
    }
}

/// One direction of an in-memory TCP stream: what one transport sends, the other reads.
private actor Pipe {
    private var bytes = Data()
    private var reader: (count: Int, continuation: CheckedContinuation<Data, Error>)?

    func write(_ data: Data) {
        bytes += data
        serve()
    }

    func read(_ count: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                reader = (count, continuation)
                serve()
            }
        } onCancel: {
            Task { await self.cancelRead() }
        }
    }

    private func serve() {
        guard let waiting = reader, bytes.count >= waiting.count else { return }
        reader = nil
        let chunk = Data(bytes.prefix(waiting.count))
        bytes.removeFirst(waiting.count)
        waiting.continuation.resume(returning: chunk)
    }

    private func cancelRead() {
        reader?.continuation.resume(throwing: CancellationError())
        reader = nil
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

        let stuck = transport.linkLog.reports
        XCTAssertEqual(stuck.count, 1)
        XCTAssertEqual(stuck.first?.toHost, true)
        XCTAssertEqual(stuck.first?.end, .open)
        XCTAssertEqual(stuck.first?.framesSent, 0)
        XCTAssertEqual(stuck.first?.waitingToSend, 3, "the send in progress and the two behind it")
        XCTAssertNotNil(stuck.first?.secondsSending, "a send is in progress")

        await tcp.releaseSend()
        await settle { transport.linkLog.reports.first?.framesSent == 3 }
        let flowing = transport.linkLog.reports.first
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

        let report = transport.linkLog.reports
        XCTAssertEqual(report.count, 1, "an ended link is still reported")
        XCTAssertEqual(report.first?.toHost, false)
        XCTAssertEqual(report.first?.end, .lost)
        XCTAssertEqual(report.first?.framesReceived, 2)
        XCTAssertEqual(report.first?.secondsSinceLastReceived, 0)

        transport.stopAll()
        XCTAssertTrue(transport.linkLog.reports.isEmpty, "a new room starts a new report")
    }

    /// Review of e833da5: a peer that stops reading fills the queue and the link is dropped. That is
    /// the clearest sign of a stall, so it must not read like an ordinary Leave.
    func testALinkDroppedForAFullQueueSaysSo() async {
        let transport = NetworkTransport()
        let tcp = HeldTCP()
        transport.open(as: PeerID(1), send: tcp.send, receiveExactly: tcp.receiveExactly)
        transport.send(Data([0]), to: PeerID(1))
        await fulfillment(of: [tcp.sending], timeout: 2)
        for _ in 0...Outbox.capacity { transport.send(Data([1]), to: PeerID(1)) }
        XCTAssertEqual(transport.linkLog.reports.first?.end, .queueFull)
        transport.stopAll()
        await tcp.releaseSend()
        await tcp.failRead()
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
        await settle { transport.linkLog.reports.first?.end == .sendFailed && transport.linkLog.reports[1].end == .closedHere }

        XCTAssertEqual(transport.linkLog.reports.map(\.end), [.sendFailed, .closedHere, .open],
                       "in the order the links opened")
        XCTAssertEqual(transport.linkLog.reports[0].waitingToSend, 0, "the failed send is not still waiting")
        XCTAssertNil(transport.linkLog.reports[0].secondsSending)
        XCTAssertNil(transport.linkLog.reports[2].secondsSinceLastReceived, "nothing ever arrived")
        transport.stopAll()
        for tcp in [failing, closed, silent] { await tcp.failRead() }
    }
    /// Device report 2026-10-11: a link the other phone closed read "bad frame", as if it had
    /// broken the framing rules.
    func testALinkTheOtherPhoneClosedSaysSo() async {
        let transport = NetworkTransport()
        let reader = ClosingReader(frames: [Data([7])])
        let ended = expectation(description: "connection closed")
        transport.onEvent = { if case .peerDisconnected = $0 { ended.fulfill() } }
        transport.open(as: PeerID(1), send: { _ in }, receiveExactly: reader.receiveExactly)
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(transport.linkLog.reports.first?.end, .closedThere)
        XCTAssertEqual(transport.linkLog.reports.first?.framesReceived, 1)
        transport.stopAll()
    }

    /// Device report 2026-10-11: the host's report was taken before its Cancel sent the abort, so a joiner
    /// had received one frame more than the host said it sent, and the reports were misread. Kept
    /// past leaving and read once the drain is over, the two now match.
    func testAfterLeavingTheHostsSentMatchesTheJoinersReceived() async {
        let host = NetworkTransport()
        let joiner = NetworkTransport()
        let up = Pipe()
        let down = Pipe()
        host.open(as: PeerID(1), send: { await down.write($0) }, receiveExactly: { try await up.read($0) })
        joiner.open(as: .host, send: { await up.write($0) }, receiveExactly: { try await down.read($0) })
        for byte in UInt8(1)...3 { host.send(Data([byte]), to: PeerID(1)) }
        await settle { joiner.linkLog.reports.first?.framesReceived == 3 }

        // Leave as the coordinator does: the abort is queued, the log is kept, then everything stops.
        host.send(Data([9]), to: PeerID(1))
        let log = host.linkLog
        host.stopAll()
        XCTAssertTrue(host.linkLog.reports.isEmpty, "the next room starts a new log")
        await settle { joiner.linkLog.reports.first?.framesReceived == 4 && log.reports.first?.framesSent == 4 }

        XCTAssertEqual(log.reports.first?.framesSent, joiner.linkLog.reports.first?.framesReceived)
        XCTAssertEqual(log.reports.first?.framesSent, 4, "the abort is counted")
        XCTAssertEqual(log.reports.first?.waitingToSend, 0)
        XCTAssertEqual(log.reports.first?.end, .leftRoom)
        joiner.stopAll()
    }

    /// A disconnect drains what was queued (an abort, a decline) before the link goes; the report
    /// counts it rather than freezing at the moment the disconnect was asked for.
    func testADisconnectCountsWhatItDrained() async {
        let transport = NetworkTransport()
        let tcp = HeldTCP()
        let link = transport.open(as: PeerID(1), send: tcp.send, receiveExactly: tcp.receiveExactly)
        transport.send(Data([1]), to: PeerID(1))
        await fulfillment(of: [tcp.sending], timeout: 2)
        transport.disconnect(PeerID(1))
        XCTAssertEqual(transport.linkLog.reports.first?.end, .closedHere)
        XCTAssertEqual(transport.linkLog.reports.first?.waitingToSend, 1)

        await tcp.releaseSend()
        await link.waitUntilClosed()
        XCTAssertEqual(transport.linkLog.reports.first?.framesSent, 1)
        XCTAssertEqual(transport.linkLog.reports.first?.waitingToSend, 0)
        XCTAssertEqual(transport.linkLog.reports.first?.end, .closedHere)
        transport.stopAll()
        await tcp.failRead()
    }

    /// Hypothesis of 2026-10-11: the peer-to-peer link dies once browsing and advertising stop. Each
    /// link says which route it took, so a stalled link can be checked against it.
    func testARouteIsNamedFromItsInterface() {
        let cases: [(NWInterface.InterfaceType, String, LinkReport.Route)] = [
            (.wifi, "awdl0", .peerToPeer), (.other, "awdl0", .peerToPeer), (.other, "llw0", .peerToPeer),
            (.wifi, "en0", .wifiNetwork), (.wiredEthernet, "en2", .wired), (.cellular, "pdp_ip0", .cellular),
            (.loopback, "lo0", .loopback), (.other, "utun3", .other),
        ]
        for (type, name, route) in cases {
            XCTAssertEqual(NetworkTransport.route(type: type, name: name), route, name)
        }
    }

    /// Review of 3e916ff: nothing documents that a path's first interface is the one in use, so a
    /// path over more than one kind says so rather than picking one.
    func testAPathOverMoreThanOneKindOfInterfaceSaysSo() {
        XCTAssertEqual(NetworkTransport.route(interfaces: []), .unknown)
        XCTAssertEqual(NetworkTransport.route(interfaces: [(.other, "awdl0")]), .peerToPeer)
        XCTAssertEqual(NetworkTransport.route(interfaces: [(.wifi, "en0"), (.wifi, "en0")]), .wifiNetwork)
        XCTAssertEqual(NetworkTransport.route(interfaces: [(.wifi, "en0"), (.wifi, "awdl0")]), .mixed)
    }

    /// Decision 2026-10-13: a room that takes nobody new keeps its registration but closes its
    /// listing. The closed listing names neither the room nor the host, and a closed room is left
    /// off the nearby list even when its listing does carry names.
    func testAClosedListingNamesNothingAndIsLeftOffTheNearbyList() {
        let open = NetworkTransport.openListing(label: "Annual bonus", size: 3, hostNickname: "Sam")
        XCTAssertEqual(NetworkTransport.advert(id: "room", txt: open),
                       RoomAdvert(id: "room", label: "Annual bonus", size: 3, hostNickname: "Sam",
                                  protocolVersion: CravageCore.protocolVersion))

        let closed = NetworkTransport.closedListing
        XCTAssertEqual(closed.dictionary.keys.sorted(), ["closed", "v"], "a closed listing still names something")
        XCTAssertNil(NetworkTransport.advert(id: "room", txt: closed))
        var namedButClosed = open
        namedButClosed["closed"] = "1"
        XCTAssertNil(NetworkTransport.advert(id: "room", txt: namedButClosed), "a closed room was put on the nearby list")
    }

    /// Review of 3e916ff: a link that has left the transport's table still reads until its close
    /// finishes, and what arrives then is counted, so the other phone's "sent" still matches.
    func testFramesThatArriveWhileALinkDrainsAreCounted() async {
        let tcp = HeldTCP()
        let incoming = Pipe()
        let transport = NetworkTransport()
        let link = transport.open(as: PeerID(1), send: tcp.send, receiveExactly: { try await incoming.read($0) })
        transport.send(Data([1]), to: PeerID(1))
        await fulfillment(of: [tcp.sending], timeout: 2)
        let delivered = expectation(description: "delivered to the engine")
        delivered.isInverted = true
        transport.onEvent = { if case .received = $0 { delivered.fulfill() } }
        transport.disconnect(PeerID(1))

        await incoming.write(try! Framing.encode(Data([5])))
        await settle { transport.linkLog.reports.first?.framesReceived == 1 }
        XCTAssertEqual(transport.linkLog.reports.first?.framesReceived, 1)
        await fulfillment(of: [delivered], timeout: 0.1)
        await tcp.releaseSend()
        await link.waitUntilClosed()
        XCTAssertEqual(transport.linkLog.reports.first?.framesReceived, 1)
        transport.stopAll()
    }

    /// The route is read as frames arrive, and the link stops holding the connection once closed.
    func testALinkReadsItsRouteAsFramesArriveAndLetsGoOfTheConnection() async {
        let transport = NetworkTransport()
        let reader = ClosingReader(frames: [Data([7])])
        let ended = expectation(description: "connection closed")
        transport.onEvent = { if case .peerDisconnected = $0 { ended.fulfill() } }
        let link = transport.open(as: PeerID(1), send: { _ in }, receiveExactly: reader.receiveExactly)
        link.currentRoute = { .peerToPeer }
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(transport.linkLog.reports.first?.route, .peerToPeer)
        XCTAssertNil(link.currentRoute, "a closed link no longer reaches its connection")
        transport.stopAll()
    }

    /// Review of 3e916ff: the log outlives the link, so a close that could not send everything
    /// lets go of the rest, after the report has counted it.
    func testAClosedLinkLetsGoOfWhatItCouldNotSend() async {
        let transport = NetworkTransport()
        let tcp = HeldTCP()
        let link = transport.open(as: PeerID(1), send: tcp.send, receiveExactly: tcp.receiveExactly)
        for byte in UInt8(1)...3 { transport.send(Data([byte]), to: PeerID(1)) }
        await fulfillment(of: [tcp.sending], timeout: 2)
        transport.disconnect(PeerID(1))
        await fulfillment(of: [tcp.sendCancelled], timeout: 5)
        await tcp.releaseSend()
        await link.waitUntilClosed()
        XCTAssertEqual(transport.linkLog.reports.first?.waitingToSend, 2, "the report counts what was left")
        XCTAssertEqual(link.outbox.waitingCount, 0, "and the frames themselves are gone")
        transport.stopAll()
        await tcp.failRead()
    }

    func testALinkReportsRouteChangesAndUnusableSpells() async {
        let transport = NetworkTransport()
        let tcp = HeldTCP()
        let link = transport.open(as: .host, send: tcp.send, receiveExactly: tcp.receiveExactly)
        XCTAssertEqual(transport.linkLog.reports.first?.route, .unknown)
        link.routeSeen(.peerToPeer)
        link.routeSeen(.peerToPeer)
        XCTAssertEqual(transport.linkLog.reports.first?.route, .peerToPeer)
        XCTAssertEqual(transport.linkLog.reports.first?.routeChanges, 0, "the first route is not a change")
        link.routeSeen(.wifiNetwork)
        link.usableChanged(false)
        link.usableChanged(false)
        link.usableChanged(true)
        link.usableChanged(false)
        let report = transport.linkLog.reports.first
        XCTAssertEqual(report?.route, .wifiNetwork)
        XCTAssertEqual(report?.routeChanges, 1)
        XCTAssertEqual(report?.timesUnusable, 2, "once per spell, however often it is repeated")
        transport.stopAll()
        await tcp.failRead()
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
