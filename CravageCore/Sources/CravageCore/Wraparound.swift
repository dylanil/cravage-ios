// Wraparound: party labels, the mask sign convention, share construction and the wrapping sum
// (docs/SPEC.md section 1; PLAN.md "Wrapping arithmetic"). Everything here is Int64 with the
// wrapping operators. Never replace `&+` / `&-` / `&*` with checked or saturating arithmetic: the
// share is a one-time pad only because addition mod 2^64 is a bijection.

import Foundation

/// A round letter A..H. Assigned by bytewise sort of verifying keys (Roster); carries no privilege.
public struct PartyLabel: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let letter: String

    public static let all: [PartyLabel] = ["A", "B", "C", "D", "E", "F", "G", "H"].map { PartyLabel(unchecked: $0) }

    /// Accepts exactly one of the eight ASCII letters A..H.
    public init?(_ string: String) {
        guard string.utf8.count == 1, let byte = string.utf8.first,
              byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "H") else { return nil }
        self.letter = string
    }

    private init(unchecked letter: String) { self.letter = letter }

    public static func < (lhs: PartyLabel, rhs: PartyLabel) -> Bool {
        lhs.letter.utf8.first! < rhs.letter.utf8.first!
    }

    public var description: String { letter }
}

public enum Wraparound {
    /// Sign convention for pair (i, j) with i < j: party i adds r_ij, party j subtracts it.
    /// Must match smpc-core.js maskSign and server.py: lower letter adds.
    public static func maskSign(_ me: PartyLabel, _ other: PartyLabel) -> Int64 {
        precondition(me != other, "a party has no pair with itself")
        return me < other ? 1 : -1
    }

    /// share = figure &+ sum over others of maskSign(me, other) &* r(me, other), mod 2^64.
    /// `pairMasks` is keyed by the other party; masks are derived by `MaskPrivateKey.mask`.
    public static func share(figure: Int64, me: PartyLabel, pairMasks: [PartyLabel: Int64]) -> Int64 {
        var share = figure
        for (other, mask) in pairMasks.sorted(by: { $0.key < $1.key }) {
            share = share &+ (maskSign(me, other) &* mask)
        }
        return share
    }

    /// The wrapping sum of all N shares. Exact as the true sum because |sum of figures| < 2^63
    /// (FixedPoint.sumOfMaxPartiesAtCapFitsInt64).
    public static func sum(_ shares: [Int64]) -> Int64 {
        shares.reduce(Int64(0)) { $0 &+ $1 }
    }

    /// Eight big-endian bytes as a signed 64-bit integer (two's complement), the conversion
    /// shared with verify_round.py and smpc-core.js for the HKDF mask output.
    public static func signedInt64BigEndian(_ bytes: Data) -> Int64 {
        precondition(bytes.count == 8, "signedInt64BigEndian needs exactly 8 bytes")
        var unsigned: UInt64 = 0
        for byte in bytes { unsigned = (unsigned << 8) | UInt64(byte) }
        return Int64(bitPattern: unsigned)
    }
}

public enum ShareStringError: Error, Equatable, Sendable {
    /// Not `^-?[0-9]+$` in canonical form (no leading zeros, no "-0").
    case malformed
    /// A canonical decimal that does not fit Int64.
    case outOfRange
}

/// Shares cross the wire and the transcript as canonical decimal strings of Int64 values:
/// `^-?[0-9]+$`, no leading zeros, no "-0", so each Int64 has exactly one spelling and
/// first-write-wins can compare strings and values interchangeably. Checked before any parse.
public enum ShareString {
    public static let maxLength = 20   // sign plus 19 digits covers all of Int64

    public static func format(_ value: Int64) -> String {
        String(value)
    }

    public static func parse(_ text: String) throws -> Int64 {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { throw ShareStringError.malformed }
        var index = 0
        if bytes[0] == UInt8(ascii: "-") { index = 1 }
        let digits = bytes[index...]
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else {
            throw ShareStringError.malformed
        }
        if digits.count > 1, digits.first == UInt8(ascii: "0") { throw ShareStringError.malformed }
        if index == 1, digits.count == 1, digits.first == UInt8(ascii: "0") { throw ShareStringError.malformed }
        guard bytes.count <= maxLength, let value = Int64(text) else { throw ShareStringError.outOfRange }
        return value
    }
}
