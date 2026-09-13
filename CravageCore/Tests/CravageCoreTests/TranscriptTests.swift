import XCTest
import Foundation
@testable import CravageCore

/// Transcript v2 (docs/SPEC.md section 4; PLAN.md TranscriptGolden). Cross-language in both
/// directions: a Python-signed golden transcript must verify here, and a Swift-produced one is
/// written to CRAVAGE_TRANSCRIPT_OUT for CI to check with Tools/check_transcript_v2.py.
final class TranscriptTests: XCTestCase {

    struct Golden: Decodable {
        struct Entry: Decodable { let scalar_hex: String; let mask_scalar_hex: String; let nickname: String; let figure: String }
        let session: String
        let label: String
        let entries: [Entry]
        let roster_hash: String
        let result_digest: String
        let shares: [String: String]
        let transcript: Transcript
    }

    private func golden() throws -> Golden {
        struct Wrapper: Decodable { let golden: Golden }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "core_vectors", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Wrapper.self, from: Data(contentsOf: url)).golden
    }

    // MARK: - Golden

    func testGoldenSharesRosterHashAndDigestMatchPython() throws {
        let g = try golden()
        let signing = try g.entries.map { try SigningKey(rawRepresentation: Data(hexString: $0.scalar_hex)) }
        let masks = try g.entries.map { try MaskPrivateKey(rawRepresentation: Data(hexString: $0.mask_scalar_hex)) }
        let entries = zip(zip(signing, masks), g.entries).map { pair, entry in
            RosterEntry(verifyingKey: pair.0.verifyingKey, maskPublicKey: pair.1.publicKey, nickname: entry.nickname)
        }
        let roster = try Roster(session: try XCTUnwrap(SessionID(hex: g.session)), label: g.label, entries: entries)
        XCTAssertEqual(Hex.encode(roster.rosterHash), g.roster_hash)

        var shares: [String: String] = [:]
        for (index, entry) in g.entries.enumerated() {
            let me = try XCTUnwrap(roster.label(for: signing[index].verifyingKey))
            var pairMasks: [PartyLabel: Int64] = [:]
            for other in roster.others(than: me) {
                pairMasks[other.label] = masks[index].mask(with: other.maskPublicKey, lo: min(me, other.label), hi: max(me, other.label))
            }
            shares[me.letter] = ShareString.format(Wraparound.share(figure: Int64(entry.figure)!, me: me, pairMasks: pairMasks))
        }
        XCTAssertEqual(shares, g.shares, "shares pinned once via Python")
        let ordered = roster.parties.map { shares[$0.label.letter]! }
        XCTAssertEqual(Wire.resultDigest(session: roster.session, rosterHash: roster.rosterHash, sharesInLetterOrder: ordered), g.result_digest)
        XCTAssertEqual(Wraparound.sum(ordered.map { Int64($0)! }), 60_000_000)
    }

    func testPythonSignedGoldenTranscriptVerifiesInSwift() throws {
        let g = try golden()
        XCTAssertEqual(TranscriptVerifier.verify(g.transcript), [])
        XCTAssertEqual(TranscriptVerifier.verify(g.transcript.encoded()), [])
        XCTAssertEqual(g.transcript.average, "20")
        XCTAssertEqual(g.transcript.claim, Transcript.claimText)
    }

    // MARK: - Swift-produced

    func testEngineRoundExportsAVerifiedTranscript() throws {
        let bus = StarBus.completed(figures: [10_000_000, 20_000_000, 30_000_000])
        let record = try XCTUnwrap(bus.engines[1].record)
        let transcript = try XCTUnwrap(Transcript.make(from: record))
        XCTAssertEqual(transcript.average, "20")
        XCTAssertEqual(transcript.sum, "60000000")
        XCTAssertEqual(TranscriptVerifier.verify(transcript.encoded()), [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: transcript.encoded()) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["format", "session", "label", "parties", "scale", "modulus", "shares", "share_sigs",
                                          "vks", "confirms", "sum", "average", "claim"])
        if let path = ProcessInfo.processInfo.environment["CRAVAGE_TRANSCRIPT_OUT"] {
            try transcript.encoded().write(to: URL(fileURLWithPath: path))
        }
    }

    func testEightPartyEdgeTranscriptWrapsAndVerifies() throws {
        let bus = StarBus.completed(figures: Array(repeating: -FixedPoint.maxMagnitude, count: 8))
        let transcript = try XCTUnwrap(Transcript.make(from: try XCTUnwrap(bus.host.record)))
        XCTAssertEqual(transcript.sum, "-7999999999999999992")
        XCTAssertEqual(TranscriptVerifier.verify(transcript), [])
    }

    func testDisagreementCannotBeExported() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.intercept = { from, _, data in
            (from == 1 && (try? Envelope.decodeAndVerify(data))?.action == .resultConfirm) ? [] : [data]
        }
        bus.submit([0: 1, 1: 2, 2: 3])
        bus.advance(ms: Deadlines.forTests.confirmationsMs)
        XCTAssertEqual(bus.host.phase, .complete(.partial(missing: [bus.engines[1].myLetter!])))
        XCTAssertNil(Transcript.make(from: try XCTUnwrap(bus.host.record)), "partial agreement is not exportable")

        let mismatch = StarBus.locked(nodes: 3)
        mismatch.confirm()
        let node2 = mismatch.engines[2].signingKey!.verifyingKey
        mismatch.intercept = { from, to, data in
            guard from == 0, to == 1, let m = try? Envelope.decodeAndVerify(data), m.action == .share, m.sender == node2 else { return [data] }
            return [mismatch.forged(by: 2, .share, content: "99")]
        }
        mismatch.submit([0: 1, 1: 2, 2: 3])
        guard case .complete(.mismatch) = mismatch.host.phase else { return XCTFail("\(mismatch.host.phase)") }
        XCTAssertNil(Transcript.make(from: try XCTUnwrap(mismatch.host.record)), "mismatched agreement is not exportable")
    }

    // MARK: - Tampering

    private func mutated(_ t: Transcript, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: t.encoded()) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testForgedShareWithRecomputedSumFailsOnlyOnTheSignatures() throws {
        let t = try golden().transcript
        let data = try mutated(t) { object in
            var shares = object["shares"] as! [String: String]
            let forged = Int64(shares["B"]!)! &+ 5_000_000
            shares["B"] = String(forged)
            object["shares"] = shares
            let total = t.parties.map { Int64(shares[$0]!)! }.reduce(Int64(0)) { $0 &+ $1 }
            object["sum"] = String(total)
            object["average"] = FixedPoint.formatAverageFixed(total, count: 3)
        }
        let failures = TranscriptVerifier.verify(data)
        XCTAssertEqual(failures, ["B: share signature does not verify under the listed key"])
    }

    func testEachTamperIsNamed() throws {
        let t = try golden().transcript
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("claim does not match the pinned text", { $0["claim"] = Transcript.claimText + " It proves identity." }),
            ("modulus is not 2^64", { $0["modulus"] = "9223372036854775808" }),
            ("scale is not 1000000", { $0["scale"] = "100" }),
            ("format is not cravage-transcript-2", { $0["format"] = "cravage-transcript-1" }),
            ("shares sum (mod 2^64) differs from the stated sum", { $0["sum"] = "60000001" }),
            ("stated average does not follow from the sum", { $0["average"] = "20.01" }),
            ("session is not a roster-bound session id", { $0["session"] = String(repeating: "ab", count: 16) }),
            ("parties must be the letters A.. in order, three to eight of them", { $0["parties"] = ["B", "A", "C"] }),
            ("confirms does not have exactly one entry per party", { object in
                var confirms = object["confirms"] as! [String: String]; confirms["C"] = nil; object["confirms"] = confirms }),
            ("C: agreement signature does not cover this exact set of shares", { object in
                var confirms = object["confirms"] as! [String: String]; confirms["C"] = confirms["A"]; object["confirms"] = confirms }),
            ("B: share is not a canonical 64-bit decimal", { object in
                var shares = object["shares"] as! [String: String]; shares["B"] = "0" + shares["B"]!; object["shares"] = shares }),
        ]
        for (expected, change) in cases {
            let failures = TranscriptVerifier.verify(try mutated(t, change))
            XCTAssertTrue(failures.contains(expected), "\(expected): got \(failures)")
        }
    }

    func testLabelIsNotSignedButSessionAndShareSetAre() throws {
        // The label is display metadata the transcript does not authenticate (the roster hash that
        // covers it cannot be recomputed from the file). Pinned so the claim text stays honest.
        let t = try golden().transcript
        XCTAssertEqual(TranscriptVerifier.verify(try mutated(t) { $0["label"] = "Something else" }), [])
        let otherSession = String(repeating: "cd", count: 16) + "." + String(t.session.split(separator: ".")[1])
        let failures = TranscriptVerifier.verify(try mutated(t) { $0["session"] = otherSession })
        XCTAssertEqual(failures.count, 3, "every share signature fails when the session changes")
    }

    func testUnreadableInputIsAFailureNotACrash() {
        for data in [Data(), Data("{}".utf8), Data("[]".utf8), Data(repeating: UInt8(ascii: "["), count: 100),
                     Data(repeating: 0x20, count: 64_001)] {
            XCTAssertEqual(TranscriptVerifier.verify(data), ["not a readable cravage-transcript-2 file"])
        }
    }
}
