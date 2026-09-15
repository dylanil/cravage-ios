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

@MainActor
final class NetworkTransportTests: XCTestCase {
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
}
