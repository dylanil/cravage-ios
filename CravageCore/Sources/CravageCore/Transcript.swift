// Transcript: the exportable record of a finished round, format "cravage-transcript-2"
// (docs/SPEC.md section 4), and its Swift verifier.
//
// What it shows, and only this (the `claim` field travels with the file and is checked byte for
// byte): the listed keys signed the listed shares, the shares sum and average as stated, and every
// listed key signed agreement to this exact set of shares. It cannot show who the participants
// were, that separate devices were involved, or that any figure was truthful or in range.
// The label is authenticated by the roomcode_confirm signatures (owner decision 2026-09-13), which
// cover roster hash, label and keys. The roster hash itself cannot be recomputed from the file,
// because it covers mask keys and nicknames the file does not carry.

import Foundation

public struct Transcript: Codable, Equatable, Sendable {
    public static let formatID = "cravage-transcript-2"
    public static let scaleString = "1000000"
    public static let modulusString = "18446744073709551616"
    public static let claimText = "This transcript shows that the listed keys signed the listed shares, that they sum and average as stated, and that every listed key signed agreement to this exact set of shares. It does not prove who the participants were, that separate devices or people were involved, or that any input was truthful."

    public let format: String
    /// The bound session: "<session hex>.<roster hash hex>", exactly as signed.
    public let session: String
    public let label: String
    public let parties: [String]
    public let scale: String
    public let modulus: String
    public let shares: [String: String]
    public let share_sigs: [String: String]
    public let vks: [String: String]
    /// result_confirm signatures, by letter.
    public let confirms: [String: String]
    /// roomcode_confirm signatures, by letter: each party's signed agreement to this label and roster.
    public let roomcode_confirms: [String: String]
    public let sum: String
    public let average: String
    public let claim: String

    /// Builds the transcript of a round in which every party signed agreement to the same shares.
    /// Returns nil for anything else (missing or mismatched agreement), so a disagreement can
    /// never be exported as if it were a verifiable result.
    public static func make(from record: RoundRecord) -> Transcript? {
        let letters = record.parties.map(\.label.letter)
        var confirms: [String: String] = [:]
        var roomcodeConfirms: [String: String] = [:]
        for party in record.parties {
            guard let signature = record.resultConfirmSignatures[party.label],
                  let roomcode = record.roomcodeConfirmSignatures[party.label] else { return nil }
            confirms[party.label.letter] = signature.base64
            roomcodeConfirms[party.label.letter] = roomcode.base64
        }
        guard record.shares.count == letters.count, record.shareSignatures.count == letters.count else { return nil }
        let transcript = Transcript(
            format: formatID,
            session: record.boundSession,
            label: record.label,
            parties: letters,
            scale: scaleString,
            modulus: modulusString,
            shares: Dictionary(uniqueKeysWithValues: record.parties.map { ($0.label.letter, record.shares[$0.label]!) }),
            share_sigs: Dictionary(uniqueKeysWithValues: record.parties.map { ($0.label.letter, record.shareSignatures[$0.label]!.base64) }),
            vks: Dictionary(uniqueKeysWithValues: record.parties.map { ($0.label.letter, $0.verifyingKey.base64) }),
            confirms: confirms,
            roomcode_confirms: roomcodeConfirms,
            sum: ShareString.format(record.sum),
            average: FixedPoint.formatAverageFixed(record.sum, count: letters.count),
            claim: claimText)
        return TranscriptVerifier.verify(transcript).isEmpty ? transcript : nil
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try! encoder.encode(self)
    }
}

/// The Swift twin of the Python v2 transcript check. Returns failure codes; empty means verified.
/// Failure strings name letters and fields only, never share values or labels.
public enum TranscriptVerifier {
    public static func verify(_ data: Data) -> [String] {
        guard data.count <= 64_000, !MessageDomain.exceedsDepth(data, cap: 4),
              let transcript = try? JSONDecoder().decode(Transcript.self, from: data) else {
            return ["not a readable cravage-transcript-2 file"]
        }
        return verify(transcript)
    }

    public static func verify(_ t: Transcript) -> [String] {
        var failures: [String] = []
        if t.format != Transcript.formatID { failures.append("format is not \(Transcript.formatID)") }
        if t.scale != Transcript.scaleString { failures.append("scale is not 1000000") }
        if t.modulus != Transcript.modulusString { failures.append("modulus is not 2^64") }
        if t.claim != Transcript.claimText { failures.append("claim does not match the pinned text") }
        guard let (session, rosterHash) = Envelope.parseBoundSession(t.session), let rosterHash else {
            return failures + ["session is not a roster-bound session id"]
        }
        let n = t.parties.count
        guard (Roster.minimumSize...Roster.maximumSize).contains(n),
              t.parties == PartyLabel.all.prefix(n).map(\.letter) else {
            return failures + ["parties must be the letters A.. in order, three to eight of them"]
        }
        let letters = Set(t.parties)
        for (name, map) in [("shares", t.shares), ("share_sigs", t.share_sigs), ("vks", t.vks), ("confirms", t.confirms),
                            ("roomcode_confirms", t.roomcode_confirms)]
        where Set(map.keys) != letters {
            failures.append("\(name) does not have exactly one entry per party")
        }
        guard failures.isEmpty else { return failures }

        var keys: [VerifyingKey] = []
        var shareValues: [Int64] = []
        for letter in t.parties {
            guard let key = try? VerifyingKey(base64: t.vks[letter]!) else {
                failures.append("\(letter): verifying key is malformed"); continue
            }
            keys.append(key)
            guard let value = try? ShareString.parse(t.shares[letter]!) else {
                failures.append("\(letter): share is not a canonical 64-bit decimal"); continue
            }
            shareValues.append(value)
            guard let signature = try? Signature(base64: t.share_sigs[letter]!) else {
                failures.append("\(letter): share signature is malformed"); continue
            }
            let canonical = CanonicalMessage(action: .share, session: t.session, party: letter, content: t.shares[letter]!)
            if !key.verify(signature, message: canonical.string) {
                failures.append("\(letter): share signature does not verify under the listed key")
            }
        }
        guard failures.isEmpty else { return failures }
        if keys != keys.sorted() || Set(keys).count != keys.count {
            failures.append("letters are not assigned by bytewise order of distinct keys")
        }

        let total = Wraparound.sum(shareValues)
        if t.sum != ShareString.format(total) { failures.append("shares sum (mod 2^64) differs from the stated sum") }
        if t.average != FixedPoint.formatAverageFixed(total, count: n) {
            failures.append("stated average does not follow from the sum")
        }

        let roomcode = Wire.roomcodeDigest(rosterHash: rosterHash, label: t.label, keysInLetterOrder: keys)
        for (letter, key) in zip(t.parties, keys) {
            guard let signature = try? Signature(base64: t.roomcode_confirms[letter]!) else {
                failures.append("\(letter): room code signature is malformed"); continue
            }
            let canonical = CanonicalMessage(action: .roomcodeConfirm, session: t.session, party: letter, content: roomcode)
            if !key.verify(signature, message: canonical.string) {
                failures.append("\(letter): room code signature does not cover this label and roster")
            }
        }

        let digest = Wire.resultDigest(session: session, rosterHash: rosterHash, sharesInLetterOrder: t.parties.map { t.shares[$0]! })
        for (letter, key) in zip(t.parties, keys) {
            guard let signature = try? Signature(base64: t.confirms[letter]!) else {
                failures.append("\(letter): agreement signature is malformed"); continue
            }
            let canonical = CanonicalMessage(action: .resultConfirm, session: t.session, party: letter, content: digest)
            if !key.verify(signature, message: canonical.string) {
                failures.append("\(letter): agreement signature does not cover this exact set of shares")
            }
        }
        return failures
    }
}
