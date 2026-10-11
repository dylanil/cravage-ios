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
        /// The stream threw (reset, timed out, failed).
        case failed
        /// The stream ended: a read came back short, between frames or inside one.
        case closed
        /// The peer broke the framing rules; the caller should close the connection.
        case rejected(FrameError)
        case cancelled
    }

    /// Throws instead of trapping: a payload out of range fails that send, it never crashes the app.
    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw FrameError.empty }
        guard payload.count <= MessageDomain.maxEnvelopeBytes else { throw FrameError.oversized }
        let length = UInt32(payload.count)
        var frame = Data([UInt8(length >> 24), UInt8((length >> 16) & 0xff), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)])
        frame.append(payload)
        return frame
    }

    /// The stream ended before a whole frame arrived.
    public struct EndOfStream: Error, Equatable, Sendable {}

    /// A read shorter than asked for is the end of the stream. The app's `receive(exactly:)` has no
    /// doc comment; on a Mac over loopback (2026-10-11) a read after the other side sent end of
    /// stream returned 0 bytes rather than throwing, and links that had ended normally on phones
    /// read as an empty frame.
    public static func readFrame(receiveExactly: @Sendable (Int) async throws -> Data) async throws -> Data {
        let header = try await receiveExactly(headerBytes)
        guard header.count == headerBytes else { throw EndOfStream() }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0 else { throw FrameError.empty }
        guard length <= MessageDomain.maxEnvelopeBytes else { throw FrameError.oversized }
        let body = try await receiveExactly(length)
        guard body.count == length else { throw EndOfStream() }
        return body
    }

    /// Reads frames until the connection ends, handing each to `deliver`. Never throws.
    public static func pump(receiveExactly: @escaping @Sendable (Int) async throws -> Data,
                            deliver: @escaping @Sendable (Data) async -> Void) async -> ConnectionEnd {
        while true {
            if Task.isCancelled { return .cancelled }
            do {
                let frame = try await readFrame(receiveExactly: receiveExactly)
                await deliver(frame)
            } catch let error as FrameError {
                return .rejected(error)
            } catch is EndOfStream {
                return .closed
            } catch {
                return Task.isCancelled ? .cancelled : .failed
            }
        }
    }
}
