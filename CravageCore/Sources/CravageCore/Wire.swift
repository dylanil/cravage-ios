// Wire: the content carried inside each envelope action (docs/SPEC.md section 3), and the two
// confirmation digests. Documented for other implementers in docs/WIRE.md.
//
//   pubkey            party = sender vk base64, session only. Content "<mask b64>|<nonce hex>|<nickname>".
//                     The joiner's hello: one signature binds the identity key, the mask key, the
//                     session and the host nonce (SPEC invariant 2).
//   control           party = "host", session only, signed by the host's round key. JSON object with
//                     "type": welcome | roster | decline | abort | restart.
//   roomcode_confirm  party = letter, bound to the roster. Content = hex of roomcodeDigest.
//   share             party = letter, bound to the roster. Content = canonical Int64 share string.
//   result_confirm    party = letter, bound to the roster. Content = hex of resultDigest.

import Foundation

public enum Wire {
    public static let hostParty = "host"

    // MARK: Hello

    public struct Hello: Hashable, Sendable {
        public let mask: MaskPublicKey
        public let nonce: String
        public let nickname: String

        public var content: String { mask.base64 + "|" + nonce + "|" + nickname }

        public init(mask: MaskPublicKey, nonce: String, nickname: String) {
            self.mask = mask
            self.nonce = nonce
            self.nickname = nickname
        }

        /// The nickname is last, so it may itself contain "|"; base64 and hex cannot.
        public static func parse(_ content: String) -> Hello? {
            let parts = content.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let mask = try? MaskPublicKey(base64: String(parts[0])),
                  isNonce(String(parts[1])),
                  RoomText.isValidNickname(String(parts[2])) else { return nil }
            return Hello(mask: mask, nonce: String(parts[1]), nickname: String(parts[2]))
        }
    }

    public static func randomNonce() -> String { SessionID.random().hex }

    static func isNonce(_ text: String) -> Bool { SessionID(hex: text) != nil }

    // MARK: Control

    /// One roster entry as the host relays it: the joiner's own signed hello, so every phone
    /// checks proof of possession and that the host did not alter anyone's mask key or nickname.
    public struct SignedHello: Codable, Hashable, Sendable {
        public let vk: String
        public let mask: String
        public let nick: String
        public let sig: String
    }

    public enum AbortReason: String, Codable, Sendable {
        case peerLeft = "peer_left"
        case timeout
        case conflict
        case rosterMismatch = "roster_mismatch"
        case hostLeft = "host_left"
    }

    public enum Control: Hashable, Sendable {
        case welcome(nonce: String, label: String, size: Int)
        case roster([SignedHello])
        case decline
        case abort(AbortReason)
        case restart(session: SessionID, nonce: String, label: String, size: Int, host: VerifyingKey)
    }

    private struct ControlJSON: Codable {
        var type: String
        var nonce: String?
        var label: String?
        var size: Int?
        var entries: [SignedHello]?
        var reason: String?
        var session: String?
        var host: String?
    }

    public static func encode(_ control: Control) -> String {
        var json = ControlJSON(type: "")
        switch control {
        case let .welcome(nonce, label, size):
            json.type = "welcome"; json.nonce = nonce; json.label = label; json.size = size
        case let .roster(entries):
            json.type = "roster"; json.entries = entries
        case .decline:
            json.type = "decline"
        case let .abort(reason):
            json.type = "abort"; json.reason = reason.rawValue
        case let .restart(session, nonce, label, size, host):
            json.type = "restart"; json.session = session.hex; json.nonce = nonce; json.label = label
            json.size = size; json.host = host.base64
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(json), as: UTF8.self)
    }

    /// Strict decode: the fields each type needs must be present and valid. Size and depth are
    /// already bounded by the envelope; the content string is checked again because it is its
    /// own JSON document.
    public static func decodeControl(_ content: String) -> Control? {
        let data = Data(content.utf8)
        guard data.count <= MessageDomain.maxEnvelopeBytes,
              !MessageDomain.exceedsDepth(data, cap: MessageDomain.maxJSONDepth),
              let json = try? JSONDecoder().decode(ControlJSON.self, from: data) else { return nil }
        switch json.type {
        case "welcome":
            guard let nonce = json.nonce, isNonce(nonce), let label = json.label, RoomText.isValidLabel(label),
                  let size = json.size, (Roster.minimumSize...Roster.maximumSize).contains(size) else { return nil }
            return .welcome(nonce: nonce, label: label, size: size)
        case "roster":
            guard let entries = json.entries, (Roster.minimumSize...Roster.maximumSize).contains(entries.count) else { return nil }
            return .roster(entries)
        case "decline":
            return .decline
        case "abort":
            guard let raw = json.reason, let reason = AbortReason(rawValue: raw) else { return nil }
            return .abort(reason)
        case "restart":
            guard let rawSession = json.session, let session = SessionID(hex: rawSession),
                  let nonce = json.nonce, isNonce(nonce), let label = json.label, RoomText.isValidLabel(label),
                  let size = json.size, (Roster.minimumSize...Roster.maximumSize).contains(size),
                  let rawHost = json.host, let host = try? VerifyingKey(base64: rawHost) else { return nil }
            return .restart(session: session, nonce: nonce, label: label, size: size, host: host)
        default:
            return nil
        }
    }

    // MARK: Digests

    /// roomcode_confirm content: SHA-256 over roster hash, room label and the verifying keys in
    /// letter order (SPEC section 3), length-prefixed and domain-tagged.
    public static func roomcodeDigest(_ roster: Roster) -> String {
        roomcodeDigest(rosterHash: roster.rosterHash, label: roster.label, keysInLetterOrder: roster.parties.map(\.verifyingKey))
    }

    /// The same digest from its parts, as a transcript verifier has them.
    public static func roomcodeDigest(rosterHash: Data, label: String, keysInLetterOrder: [VerifyingKey]) -> String {
        var encoder = LengthPrefixedEncoder(tag: "cravage-roomcode-confirm-1")
        encoder.append(rosterHash)
        encoder.append(label)
        encoder.appendByte(UInt8(keysInLetterOrder.count))
        for key in keysInLetterOrder { encoder.append(key.x963) }
        return Hex.encode(Digest.sha256(encoder.bytes))
    }

    /// result_confirm content: SHA-256 over session id, roster hash and the shares in letter
    /// order (SPEC section 3), length-prefixed and domain-tagged.
    public static func resultDigest(session: SessionID, rosterHash: Data, sharesInLetterOrder: [String]) -> String {
        var encoder = LengthPrefixedEncoder(tag: "cravage-result-confirm-1")
        encoder.append(session.hex)
        encoder.append(rosterHash)
        encoder.appendByte(UInt8(sharesInLetterOrder.count))
        for share in sharesInLetterOrder { encoder.append(share) }
        return Hex.encode(Digest.sha256(encoder.bytes))
    }
}
