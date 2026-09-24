// Roster: who is in a locked round, their letters, the roster hash every message is bound to,
// and the room fingerprint people compare out loud (PLAN.md "PartyLabel", "RoomFingerprint";
// docs/SPEC.md section 3 invariant 2). Also the canonical message string that is signed.
//
// Encodings are length-prefixed (4-byte big-endian length, then bytes) with a domain tag, so no
// field boundary is ambiguous. Tools/gen_core_fixtures.py carries a second implementation of
// both hashes; the fixture pins them.

import Foundation

/// A round's session id: 16 random bytes as 32 lowercase hex characters. Fresh on every round
/// and restart; every message carries it and messages from another session are rejected.
public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let hex: String

    public static func random() -> SessionID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return SessionID(hex: bytes.map { String(format: "%02x", $0) }.joined())!
    }

    public init?(hex: String) {
        guard hex.utf8.count == 32,
              hex.utf8.allSatisfy({ ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")) || ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "f")) })
        else { return nil }
        self.hex = hex
    }

    public var description: String { hex }
}

/// Bounds for the two human-entered strings that reach other phones. Both are untrusted on
/// receipt: bounded in bytes, no control characters, no bidirectional overrides, no invisible
/// characters, no leading or trailing whitespace. Neither is identity.
///
/// Invisible means a character that draws nothing: Unicode format characters and default-ignorable
/// code points (zero-width spaces and joiners, variation selectors, tag characters, Hangul fillers),
/// plus the blank Braille pattern. Without this rule two names can look identical and differ
/// underneath (owner decision 2026-09-24). Emoji built with an invisible joiner or style marker
/// are refused as a result, by choice.
public enum RoomText {
    public static let maxLabelBytes = 120
    public static let maxNicknameBytes = 48

    public static func isValidLabel(_ text: String) -> Bool { isValid(text, maxBytes: maxLabelBytes) }
    public static func isValidNickname(_ text: String) -> Bool { isValid(text, maxBytes: maxNicknameBytes) }

    private static func isValid(_ text: String, maxBytes: Int) -> Bool {
        guard !text.isEmpty, text.utf8.count <= maxBytes else { return false }
        guard let first = text.unicodeScalars.first, let last = text.unicodeScalars.last,
              !first.properties.isWhitespace, !last.properties.isWhitespace else { return false }
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return false
            default: break
            }
            if bidiControls.contains(scalar) { return false }
            if isInvisible(scalar) { return false }
        }
        return true
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format || scalar.properties.isDefaultIgnorableCodePoint
            || scalar == "\u{2800}"
    }

    private static let bidiControls: Set<Unicode.Scalar> = [
        "\u{061C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{FEFF}",
    ]
}

/// What a joiner's signed hello contributes to the roster.
public struct RosterEntry: Hashable, Sendable {
    public let verifyingKey: VerifyingKey
    public let maskPublicKey: MaskPublicKey
    public let nickname: String

    public init(verifyingKey: VerifyingKey, maskPublicKey: MaskPublicKey, nickname: String) {
        self.verifyingKey = verifyingKey
        self.maskPublicKey = maskPublicKey
        self.nickname = nickname
    }
}

/// A roster entry with its assigned letter.
public struct Party: Hashable, Sendable {
    public let label: PartyLabel
    public let verifyingKey: VerifyingKey
    public let maskPublicKey: MaskPublicKey
    public let nickname: String
}

public enum RosterError: Error, Equatable, Sendable {
    case sizeOutOfRange
    case duplicateKey
    case invalidLabel
    case invalidNickname
}

/// The locked roster of a round. Letters A.. are assigned by bytewise order of verifying keys;
/// every phone recomputes them and they carry no privilege.
public struct Roster: Hashable, Sendable {
    public static let minimumSize = 3
    public static let maximumSize = FixedPoint.maxParties

    public let session: SessionID
    public let label: String
    /// In letter order.
    public let parties: [Party]
    /// SHA-256 over session, size and every party's keys and nickname in letter order. Bound into
    /// every signed message. Does not cover the room label; the fingerprint does.
    public let rosterHash: Data
    public let fingerprint: RoomFingerprint

    public var size: Int { parties.count }

    public init(session: SessionID, label: String, entries: [RosterEntry]) throws {
        guard (Roster.minimumSize...Roster.maximumSize).contains(entries.count) else { throw RosterError.sizeOutOfRange }
        guard RoomText.isValidLabel(label) else { throw RosterError.invalidLabel }
        var seenPoints = Set<Data>()
        for entry in entries {
            guard RoomText.isValidNickname(entry.nickname) else { throw RosterError.invalidNickname }
            // A point reused anywhere in the roster, as either kind of key, is ambiguous.
            guard seenPoints.insert(entry.verifyingKey.x963).inserted,
                  seenPoints.insert(entry.maskPublicKey.x963).inserted else { throw RosterError.duplicateKey }
        }
        let ordered = entries.sorted { $0.verifyingKey < $1.verifyingKey }
        self.session = session
        self.label = label
        self.parties = zip(PartyLabel.all, ordered).map { label, entry in
            Party(label: label, verifyingKey: entry.verifyingKey, maskPublicKey: entry.maskPublicKey, nickname: entry.nickname)
        }
        var encoder = LengthPrefixedEncoder(tag: "cravage-roster-1")
        encoder.append(session.hex)
        encoder.appendByte(UInt8(parties.count))
        for party in parties {
            encoder.append(party.verifyingKey.x963)
            encoder.append(party.maskPublicKey.x963)
            encoder.append(party.nickname)
        }
        self.rosterHash = Digest.sha256(encoder.bytes)
        self.fingerprint = RoomFingerprint(session: session, label: label, size: parties.count, rosterHash: rosterHash)
    }

    public func label(for key: VerifyingKey) -> PartyLabel? {
        parties.first { $0.verifyingKey == key }?.label
    }

    /// The party holding `label`. Traps on a letter outside this roster: callers obtain letters
    /// from this roster, so an unknown letter is a programming error, not peer input.
    public func party(_ label: PartyLabel) -> Party {
        guard let party = parties.first(where: { $0.label == label }) else {
            preconditionFailure("letter \(label) is not in this roster")
        }
        return party
    }

    public func contains(_ label: PartyLabel) -> Bool {
        parties.contains { $0.label == label }
    }

    public func others(than me: PartyLabel) -> [Party] {
        parties.filter { $0.label != me }
    }
}

/// The code everyone in the room compares: SHA-256 over session, label, size and the roster
/// hash; first 5 bytes (40 bits) as Crockford base32, XXXX-XXXX. Matching codes mean matching
/// rooms except with negligible probability; a differing label or key changes the code.
public struct RoomFingerprint: Hashable, Sendable, CustomStringConvertible {
    public let code: String

    init(session: SessionID, label: String, size: Int, rosterHash: Data) {
        var encoder = LengthPrefixedEncoder(tag: "cravage-fingerprint-1")
        encoder.append(session.hex)
        encoder.append(label)
        encoder.appendByte(UInt8(size))
        encoder.append(rosterHash)
        self.code = RoomFingerprint.crockford(Digest.sha256(encoder.bytes).prefix(5))
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Crockford base32 of exactly 5 bytes as 8 symbols with a dash after the fourth.
    static func crockford(_ five: Data) -> String {
        precondition(five.count == 5, "the fingerprint takes exactly 5 bytes")
        var value: UInt64 = 0
        for byte in five { value = (value << 8) | UInt64(byte) }
        var symbols: [Character] = []
        for index in 0..<8 {
            let shift = UInt64(35 - 5 * index)
            symbols.append(alphabet[Int((value >> shift) & 31)])
        }
        return String(symbols[0..<4]) + "-" + String(symbols[4..<8])
    }

    public var description: String { code }
}

/// Length-prefixed byte encoding shared by the roster hash and the fingerprint.
struct LengthPrefixedEncoder {
    private(set) var bytes = Data()

    init(tag: String) { append(tag) }

    mutating func append(_ data: Data) {
        let length = UInt32(data.count)
        bytes.append(contentsOf: [UInt8(length >> 24), UInt8((length >> 16) & 0xff), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)])
        bytes.append(data)
    }

    mutating func append(_ string: String) { append(Data(string.utf8)) }

    mutating func appendByte(_ byte: UInt8) { bytes.append(byte) }
}

// MARK: - Canonical message

/// The action set from docs/SPEC.md section 3. `roomcode_confirm` and `result_confirm` are
/// distinct cases on purpose: they must never share a verifier.
public enum MessageAction: String, CaseIterable, Sendable {
    case pubkey
    case share
    case roomcodeConfirm = "roomcode_confirm"
    case resultConfirm = "result_confirm"
    case control
}

/// The bytes that are signed: "<action>|<session>|<party>|<content>", matching smpc-core.js
/// canonicalMessage and verify_round.py canonical. Constructed on both sides from structured
/// fields, never parsed.
public struct CanonicalMessage: Hashable, Sendable {
    public let action: MessageAction
    public let session: String
    public let party: String
    public let content: String

    public init(action: MessageAction, session: String, party: String, content: String) {
        self.action = action
        self.session = session
        self.party = party
        self.content = content
    }

    public var string: String { "\(action.rawValue)|\(session)|\(party)|\(content)" }
}
