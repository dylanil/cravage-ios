// Roster: who is in a locked round, their letters, the roster hash every message is bound to,
// and the room fingerprint people compare out loud (PLAN.md "PartyLabel", "RoomFingerprint";
// docs/SPEC.md section 3 invariant 2). Also the canonical message string that is signed.
//
// Encodings are length-prefixed (4-byte big-endian length, then bytes) with a domain tag, so no
// field boundary is ambiguous. Tools/gen_core_fixtures.py carries a second implementation of
// both hashes; the fixture pins them.

import Foundation
import Security

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
/// plus the blank Braille pattern (decision 2026-09-24). This removes the characters that draw
/// nothing at all; it does not make look-alike names impossible (other spaces, composed and
/// decomposed accents, letters from other scripts still differ underneath), which is why names
/// are never identity. The two joiners some scripts need are allowed between visible characters
/// (option B); emoji carrying an invisible style marker, such as the red heart, are refused.
public enum RoomText {
    public static let maxLabelBytes = 120
    public static let maxNicknameBytes = 48

    public static func isValidLabel(_ text: String) -> Bool { isValid(text, maxBytes: maxLabelBytes) }
    public static func isValidNickname(_ text: String) -> Bool { isValid(text, maxBytes: maxNicknameBytes) }

    private static func isValid(_ text: String, maxBytes: Int) -> Bool {
        guard !text.isEmpty, text.utf8.count <= maxBytes else { return false }
        guard let first = text.unicodeScalars.first, let last = text.unicodeScalars.last,
              !first.properties.isWhitespace, !last.properties.isWhitespace else { return false }
        let scalars = Array(text.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return false
            default: break
            }
            if bidiControls.contains(scalar) { return false }
            if joiners.contains(scalar) {
                if !isJoinerBetweenVisibleCharacters(scalars, at: index) { return false }
            } else if isInvisible(scalar) {
                return false
            }
        }
        return true
    }

    /// Zero-width non-joiner and joiner: Persian, Sinhala, Devanagari and other scripts need them to
    /// spell some names, and some emoji are built with them (decision 2026-09-24, option B).
    private static let joiners: Set<Unicode.Scalar> = ["\u{200C}", "\u{200D}"]

    /// A joiner is allowed only with a visible character on each side, never at an edge, next to
    /// another invisible character or next to whitespace.
    private static func isJoinerBetweenVisibleCharacters(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard index > 0, index < scalars.count - 1 else { return false }
        return [scalars[index - 1], scalars[index + 1]].allSatisfy { neighbour in
            !joiners.contains(neighbour) && !isInvisible(neighbour) && !neighbour.properties.isWhitespace
        }
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
    /// The party's room-code seal (`RoomCodeSeal.commitment`), 32 bytes.
    public let commitment: Data
    public let nickname: String

    public init(verifyingKey: VerifyingKey, maskPublicKey: MaskPublicKey, commitment: Data, nickname: String) {
        self.verifyingKey = verifyingKey
        self.maskPublicKey = maskPublicKey
        self.commitment = commitment
        self.nickname = nickname
    }
}

/// A roster entry with its assigned letter.
public struct Party: Hashable, Sendable {
    public let label: PartyLabel
    public let verifyingKey: VerifyingKey
    public let maskPublicKey: MaskPublicKey
    public let commitment: Data
    public let nickname: String
}

public enum RosterError: Error, Equatable, Sendable {
    case sizeOutOfRange
    case duplicateKey
    case invalidLabel
    case invalidNickname
    case invalidCommitment
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
    /// SHA-256 over session, size and every party's keys, seal and nickname in letter order. Bound
    /// into every signed message. Does not cover the room label; the room code does.
    public let rosterHash: Data

    public var size: Int { parties.count }

    public init(session: SessionID, label: String, entries: [RosterEntry]) throws {
        guard (Roster.minimumSize...Roster.maximumSize).contains(entries.count) else { throw RosterError.sizeOutOfRange }
        guard RoomText.isValidLabel(label) else { throw RosterError.invalidLabel }
        var seenPoints = Set<Data>()
        for entry in entries {
            guard RoomText.isValidNickname(entry.nickname) else { throw RosterError.invalidNickname }
            guard entry.commitment.count == RoomCodeSeal.valueBytes else { throw RosterError.invalidCommitment }
            // A point reused anywhere in the roster, as either kind of key, is ambiguous.
            guard seenPoints.insert(entry.verifyingKey.x963).inserted,
                  seenPoints.insert(entry.maskPublicKey.x963).inserted else { throw RosterError.duplicateKey }
        }
        let ordered = entries.sorted { $0.verifyingKey < $1.verifyingKey }
        self.session = session
        self.label = label
        self.parties = zip(PartyLabel.all, ordered).map { label, entry in
            Party(label: label, verifyingKey: entry.verifyingKey, maskPublicKey: entry.maskPublicKey,
                  commitment: entry.commitment, nickname: entry.nickname)
        }
        var encoder = LengthPrefixedEncoder(tag: "cravage-roster-2")
        encoder.append(session.hex)
        encoder.appendByte(UInt8(parties.count))
        for party in parties {
            encoder.append(party.verifyingKey.x963)
            encoder.append(party.maskPublicKey.x963)
            encoder.append(party.commitment)
            encoder.append(party.nickname)
        }
        self.rosterHash = Digest.sha256(encoder.bytes)
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

/// The room-code seal (council 2026-10-03; SPEC section 3 invariant 14). Every party draws a
/// fresh random value with its keys, puts only its commitment in the signed hello, and reveals the
/// value once it holds the locked roster, which carries every commitment. Nobody, the host and any
/// participants it invents included, can then pick a value after seeing an honest one.
public enum RoomCodeSeal {
    public static let valueBytes = 32

    /// 32 bytes from `SecRandomCopyBytes`. Security.framework's SecRandom.h documents
    /// `kSecRandomDefault` as "a cryptographically secure random number generator".
    public static func randomValue() -> Data {
        var bytes = [UInt8](repeating: 0, count: valueBytes)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "the system random generator failed")
        return Data(bytes)
    }

    /// SHA-256 over session, verifying key, room label and value, untruncated. The key keeps one
    /// party's seal from being reused by another; the session keeps it from another round.
    public static func commitment(session: SessionID, verifyingKey: VerifyingKey, label: String, value: Data) -> Data {
        var encoder = LengthPrefixedEncoder(tag: "cravage-roomcode-commit-1")
        encoder.append(session.hex)
        encoder.append(verifyingKey.x963)
        encoder.append(label)
        encoder.append(value)
        return Digest.sha256(encoder.bytes)
    }
}

/// The code everyone in the room compares: SHA-256 over session, label, size, the roster hash and
/// every party's revealed seal value in letter order; first 5 bytes (40 bits) as Crockford base32,
/// XXXX-XXXX. The host chooses most of these inputs and can invent participants, so a code it
/// could compute in advance would only need a birthday search to match across two rooms. The
/// revealed values close that: each phone's code depends on its own value, which nobody knew when
/// the roster was fixed, so two different rooms match with probability 2^-40 per attempt. A failed
/// attempt ends the round visibly (a timeout, an abort or a phone leaving), and another needs
/// everyone to accept a restart.
public struct RoomFingerprint: Hashable, Sendable, CustomStringConvertible {
    public let code: String

    init(roster: Roster, revealsInLetterOrder: [Data]) {
        self.code = RoomFingerprint.crockford(RoomFingerprint.digest(roster: roster, revealsInLetterOrder: revealsInLetterOrder).prefix(5))
    }

    /// The full digest the code is cut from; tests narrow it to show the attack at a runnable width.
    static func digest(roster: Roster, revealsInLetterOrder: [Data]) -> Data {
        var encoder = LengthPrefixedEncoder(tag: "cravage-fingerprint-2")
        encoder.append(roster.session.hex)
        encoder.append(roster.label)
        encoder.appendByte(UInt8(roster.size))
        encoder.append(roster.rosterHash)
        for value in revealsInLetterOrder { encoder.append(value) }
        return Digest.sha256(encoder.bytes)
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
/// distinct cases on purpose: they must never share a verifier. `roomcode_dispute` is the signed
/// "The codes don't match" (2026-10-04).
public enum MessageAction: String, CaseIterable, Sendable {
    case pubkey
    case share
    case roomcodeReveal = "roomcode_reveal"
    case roomcodeConfirm = "roomcode_confirm"
    case roomcodeDispute = "roomcode_dispute"
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
