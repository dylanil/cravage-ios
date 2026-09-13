// Envelope: the signed JSON wire message and the domain limits applied before anything is
// decoded or verified (PLAN.md "Message domain limits"; SPEC section 3). The transport hands
// bytes to `Envelope.decodeAndVerify`; the engine only ever sees a `VerifiedMessage`.
//
// Fields: v (protocol version), session (hex), action, party, sender (verifying key, base64),
// content, sig (raw r||s, base64). The signature covers the canonical string
// "<action>|<session>|<party>|<content>" under the sender's key. Unknown fields are ignored.

import Foundation

public enum MessageDomain {
    /// Largest envelope accepted, in bytes, checked before parsing. A locked roster for eight
    /// parties with every signed hello is under 4 KB.
    public static let maxEnvelopeBytes = 8192
    /// Deepest JSON nesting accepted, checked by a linear scan before parsing.
    public static let maxJSONDepth = 6

    /// Depth of the deepest array or object in `data`, ignoring brackets inside strings.
    /// Stops early once the cap is exceeded.
    static func exceedsDepth(_ data: Data, cap: Int) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                if depth > cap { return true }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            default: break
            }
        }
        return false
    }
}

public enum MessageError: Error, Equatable, Sendable {
    case tooLarge
    case tooDeep
    /// Not this protocol's version: the UI shows "update the app".
    case unsupportedVersion(Int)
    case malformed
    case unknownAction
    case badSignature
}

/// A message after its signature has been verified under `sender`. The engine still has to
/// decide whether `sender` is allowed to speak as `party` in this session.
public struct VerifiedMessage: Hashable, Sendable {
    public let session: SessionID
    public let action: MessageAction
    public let party: String
    public let sender: VerifyingKey
    public let content: String

    public var canonical: CanonicalMessage {
        CanonicalMessage(action: action, session: session.hex, party: party, content: content)
    }
}

public struct Envelope: Codable, Hashable, Sendable {
    public let v: Int
    public let session: String
    public let action: String
    public let party: String
    public let sender: String
    public let content: String
    public let sig: String

    /// Builds and signs an envelope under `key`.
    public static func signed(action: MessageAction, session: SessionID, party: String, content: String,
                              key: SigningKey) -> Envelope {
        let canonical = CanonicalMessage(action: action, session: session.hex, party: party, content: content)
        return Envelope(v: CravageCore.protocolVersion, session: session.hex, action: action.rawValue, party: party,
                        sender: key.verifyingKey.base64, content: content, sig: key.sign(canonical.string).base64)
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings and an Int cannot fail.
        return try! encoder.encode(self)
    }

    private struct VersionProbe: Decodable { let v: Int }

    /// Size, depth, version, shape, action, key and signature checks, in that order, so the
    /// cheap rejections happen first and no crypto runs on oversized or malformed input.
    public static func decodeAndVerify(_ data: Data) throws -> VerifiedMessage {
        guard data.count <= MessageDomain.maxEnvelopeBytes else { throw MessageError.tooLarge }
        guard !MessageDomain.exceedsDepth(data, cap: MessageDomain.maxJSONDepth) else { throw MessageError.tooDeep }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { throw MessageError.malformed }
        guard probe.v == CravageCore.protocolVersion else { throw MessageError.unsupportedVersion(probe.v) }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw MessageError.malformed }
        guard let action = MessageAction(rawValue: envelope.action) else { throw MessageError.unknownAction }
        guard let session = SessionID(hex: envelope.session),
              let sender = try? VerifyingKey(base64: envelope.sender),
              let signature = try? Signature(base64: envelope.sig) else { throw MessageError.malformed }
        let canonical = CanonicalMessage(action: action, session: session.hex, party: envelope.party, content: envelope.content)
        guard sender.verify(signature, message: canonical.string) else { throw MessageError.badSignature }
        return VerifiedMessage(session: session, action: action, party: envelope.party, sender: sender, content: envelope.content)
    }
}
