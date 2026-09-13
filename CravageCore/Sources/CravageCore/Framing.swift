// Framing: how envelopes travel over a TCP stream, and the per-connection receive loop the app's
// NetworkTransport runs. No Network import: the transport hands in its `receive(exactly:)`.
//
// Frame = 4-byte big-endian length, then that many bytes. The length is checked against
// MessageDomain.maxEnvelopeBytes before the body is read, so a peer cannot make a phone allocate
// or wait for more than one envelope's worth of bytes.

import Foundation

public enum Framing {
    public static let headerBytes = 4

    public enum FrameError: Error, Equatable, Sendable {
        case empty
        case oversized
    }

    /// How a connection's receive loop ended. The caller cleans up after `pump` returns, whatever
    /// the case, so cleanup can never be skipped by a thrown error.
    public enum ConnectionEnd: Equatable, Sendable {
        /// The stream threw (closed, reset, timed out): the normal way a connection ends.
        case failed
        /// The peer broke the framing rules; the caller should close the connection.
        case rejected(FrameError)
        case cancelled
    }

    public static func encode(_ payload: Data) -> Data {
        precondition(!payload.isEmpty && payload.count <= MessageDomain.maxEnvelopeBytes, "frame payload out of range")
        let length = UInt32(payload.count)
        var frame = Data([UInt8(length >> 24), UInt8((length >> 16) & 0xff), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)])
        frame.append(payload)
        return frame
    }

    public static func readFrame(receiveExactly: (Int) async throws -> Data) async throws -> Data {
        let header = try await receiveExactly(headerBytes)
        guard header.count == headerBytes else { throw FrameError.empty }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0 else { throw FrameError.empty }
        guard length <= MessageDomain.maxEnvelopeBytes else { throw FrameError.oversized }
        return try await receiveExactly(length)
    }

    /// Reads frames until the connection ends, handing each to `deliver`. Never throws.
    public static func pump(receiveExactly: (Int) async throws -> Data, deliver: (Data) async -> Void) async -> ConnectionEnd {
        while true {
            if Task.isCancelled { return .cancelled }
            do {
                let frame = try await readFrame(receiveExactly: receiveExactly)
                await deliver(frame)
            } catch let error as FrameError {
                return .rejected(error)
            } catch {
                return Task.isCancelled ? .cancelled : .failed
            }
        }
    }
}
