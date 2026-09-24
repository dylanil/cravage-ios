import XCTest
import Foundation
@testable import CravageCore

/// Roster, letter assignment, roster hash, room fingerprint and canonical message (PLAN.md
/// "PartyLabel", "RoomFingerprint", "CanonicalMessage"; SPEC section 3 invariant 2).
final class RosterTests: XCTestCase {

    struct RosterVector: Decodable {
        struct Entry: Decodable { let scalar_hex: String; let mask_scalar_hex: String; let nickname: String }
        let session: String
        let label: String
        let entries: [Entry]
        let letters: [String]
        let roster_hash: String
        let fingerprint: String
    }
    struct RosterVectors: Decodable { let rosters: [RosterVector] }

    private func makeEntry(_ signingScalar: UInt8, _ maskScalar: UInt8, nickname: String = "n") throws -> RosterEntry {
        RosterEntry(
            verifyingKey: try SigningKey(rawRepresentation: Data(repeating: signingScalar, count: 32)).verifyingKey,
            maskPublicKey: try MaskPrivateKey(rawRepresentation: Data(repeating: maskScalar, count: 32)).publicKey,
            nickname: nickname)
    }

    private func threeEntries() throws -> [RosterEntry] {
        [try makeEntry(1, 11, nickname: "one"), try makeEntry(2, 12, nickname: "two"), try makeEntry(3, 13, nickname: "three")]
    }

    private let session = SessionID(hex: String(repeating: "ab", count: 16))!

    // MARK: - Session id

    func testSessionIDIsSixteenRandomBytesAsLowercaseHex() {
        let a = SessionID.random(), b = SessionID.random()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.hex.count, 32)
        XCTAssertTrue(a.hex.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(SessionID(hex: a.hex), a)
        for bad in ["", "AB", String(repeating: "AB", count: 16), String(repeating: "zz", count: 16),
                    String(repeating: "ab", count: 15), String(repeating: "ab", count: 17), "ab|" + String(repeating: "a", count: 29)] {
            XCTAssertNil(SessionID(hex: bad), bad)
        }
    }

    // MARK: - Construction rules

    func testLettersFollowBytewiseOrderOfVerifyingKeys() throws {
        let entries = try threeEntries()
        let roster = try Roster(session: session, label: "Salary", entries: entries.reversed())
        let sortedKeys = entries.map(\.verifyingKey).sorted()
        XCTAssertEqual(roster.parties.map(\.verifyingKey), sortedKeys)
        XCTAssertEqual(roster.parties.map(\.label), Array(PartyLabel.all.prefix(3)))
        for entry in entries {
            let label = try XCTUnwrap(roster.label(for: entry.verifyingKey))
            XCTAssertEqual(roster.party(label).verifyingKey, entry.verifyingKey)
            XCTAssertEqual(roster.party(label).maskPublicKey, entry.maskPublicKey)
            XCTAssertEqual(roster.party(label).nickname, entry.nickname)
        }
        XCTAssertNil(roster.label(for: SigningKey().verifyingKey))
        XCTAssertEqual(roster.size, 3)
        XCTAssertEqual(roster.others(than: PartyLabel("B")!).map(\.label), [PartyLabel("A")!, PartyLabel("C")!])
    }

    func testRosterSizeMustBeThreeToEight() throws {
        var entries: [RosterEntry] = []
        for i in 1...9 { entries.append(try makeEntry(UInt8(i), UInt8(100 + i))) }
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: [])) {
            XCTAssertEqual($0 as? RosterError, .sizeOutOfRange)
        }
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: Array(entries.prefix(2)))) {
            XCTAssertEqual($0 as? RosterError, .sizeOutOfRange)
        }
        for n in 3...8 {
            XCTAssertEqual(try Roster(session: session, label: "l", entries: Array(entries.prefix(n))).size, n)
        }
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: entries)) {
            XCTAssertEqual($0 as? RosterError, .sizeOutOfRange)
        }
        XCTAssertEqual(Roster.minimumSize, 3)
        XCTAssertEqual(Roster.maximumSize, FixedPoint.maxParties)
    }

    func testDuplicateOrAmbiguousKeysAreRejected() throws {
        let entries = try threeEntries()
        let dupVK = RosterEntry(verifyingKey: entries[0].verifyingKey, maskPublicKey: try makeEntry(9, 99).maskPublicKey, nickname: "x")
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: entries + [dupVK])) {
            XCTAssertEqual($0 as? RosterError, .duplicateKey)
        }
        let dupMask = RosterEntry(verifyingKey: try makeEntry(9, 99).verifyingKey, maskPublicKey: entries[1].maskPublicKey, nickname: "x")
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: entries + [dupMask])) {
            XCTAssertEqual($0 as? RosterError, .duplicateKey)
        }
        // The same point used as one party's verifying key and another's mask key is ambiguous.
        let crossScalar = Data(repeating: 7, count: 32)
        let crossVK = try SigningKey(rawRepresentation: crossScalar).verifyingKey
        let crossMask = try MaskPrivateKey(rawRepresentation: crossScalar).publicKey
        XCTAssertEqual(crossVK.x963, crossMask.x963, "same scalar, same point")
        let one = RosterEntry(verifyingKey: crossVK, maskPublicKey: try makeEntry(9, 99).maskPublicKey, nickname: "x")
        let two = RosterEntry(verifyingKey: try makeEntry(8, 88).verifyingKey, maskPublicKey: crossMask, nickname: "y")
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: entries + [one, two])) {
            XCTAssertEqual($0 as? RosterError, .duplicateKey)
        }
        // A single party whose two keys are the same point is ambiguous too.
        let same = RosterEntry(verifyingKey: crossVK, maskPublicKey: crossMask, nickname: "z")
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: entries + [same])) {
            XCTAssertEqual($0 as? RosterError, .duplicateKey)
        }
    }

    func testLabelAndNicknameBoundsAreEnforced() throws {
        let entries = try threeEntries()
        XCTAssertThrowsError(try Roster(session: session, label: "", entries: entries)) {
            XCTAssertEqual($0 as? RosterError, .invalidLabel)
        }
        XCTAssertThrowsError(try Roster(session: session, label: String(repeating: "x", count: RoomText.maxLabelBytes + 1), entries: entries)) {
            XCTAssertEqual($0 as? RosterError, .invalidLabel)
        }
        XCTAssertThrowsError(try Roster(session: session, label: "line\nbreak", entries: entries)) {
            XCTAssertEqual($0 as? RosterError, .invalidLabel)
        }
        XCTAssertNoThrow(try Roster(session: session, label: String(repeating: "x", count: RoomText.maxLabelBytes), entries: entries))
        XCTAssertNoThrow(try Roster(session: session, label: "Average bonus (\u{00a3}) \u{2603}", entries: entries))
        var badNick = entries
        badNick[0] = RosterEntry(verifyingKey: entries[0].verifyingKey, maskPublicKey: entries[0].maskPublicKey, nickname: "")
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: badNick)) {
            XCTAssertEqual($0 as? RosterError, .invalidNickname)
        }
        badNick[0] = RosterEntry(verifyingKey: entries[0].verifyingKey, maskPublicKey: entries[0].maskPublicKey,
                                 nickname: String(repeating: "n", count: RoomText.maxNicknameBytes + 1))
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: badNick)) {
            XCTAssertEqual($0 as? RosterError, .invalidNickname)
        }
        badNick[0] = RosterEntry(verifyingKey: entries[0].verifyingKey, maskPublicKey: entries[0].maskPublicKey, nickname: "tab\there")
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: badNick)) {
            XCTAssertEqual($0 as? RosterError, .invalidNickname)
        }
    }

    func testRoomTextRules() {
        XCTAssertTrue(RoomText.isValidLabel("Average salary"))
        XCTAssertTrue(RoomText.isValidLabel("a"))
        XCTAssertFalse(RoomText.isValidLabel(""))
        XCTAssertFalse(RoomText.isValidLabel(" "))
        XCTAssertFalse(RoomText.isValidLabel(" padded"))
        XCTAssertFalse(RoomText.isValidLabel("padded "))
        XCTAssertFalse(RoomText.isValidLabel("nul\u{0000}"))
        XCTAssertFalse(RoomText.isValidLabel("esc\u{001b}[31m"))
        XCTAssertFalse(RoomText.isValidLabel("del\u{007f}"))
        XCTAssertFalse(RoomText.isValidLabel("bidi\u{202e}"))
        XCTAssertFalse(RoomText.isValidLabel(String(repeating: "\u{00a3}", count: RoomText.maxLabelBytes / 2 + 1)), "bytes, not characters")
        XCTAssertTrue(RoomText.isValidNickname("Dee"))
        XCTAssertFalse(RoomText.isValidNickname(""))
        XCTAssertFalse(RoomText.isValidNickname(String(repeating: "n", count: RoomText.maxNicknameBytes + 1)))
        XCTAssertTrue(RoomText.isValidNickname(String(repeating: "n", count: RoomText.maxNicknameBytes)))
        XCTAssertLessThanOrEqual(RoomText.maxNicknameBytes, RoomText.maxLabelBytes)
    }

    // MARK: - Hash and fingerprint

    /// Owner decision 2026-09-24: a name or label may not carry characters that draw nothing, so
    /// two people cannot show identical-looking names that differ underneath. Emoji built with an
    /// invisible joiner or style marker (such as the red heart) are refused too, by choice.
    func testInvisibleCharactersAreRejectedInNamesAndLabels() {
        let invisible: [String] = [
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{00AD}", "\u{034F}", "\u{180E}",
            "\u{FE0F}", "\u{E0041}", "\u{3164}", "\u{FFA0}", "\u{2800}",
        ]
        for scalar in invisible {
            let name = "Pat" + scalar + "x"
            XCTAssertFalse(RoomText.isValidNickname(name), "accepted \(name.unicodeScalars.map { String($0.value, radix: 16) })")
            XCTAssertFalse(RoomText.isValidLabel("Bonus" + scalar + "x"))
        }
        XCTAssertFalse(RoomText.isValidNickname("\u{2764}\u{FE0F}"), "the red heart carries an invisible style marker")
        XCTAssertNil(Wire.Hello.parse(MaskPrivateKey().publicKey.base64 + "|" + Wire.randomNonce() + "|Pat\u{200B}"),
                     "a hello from another phone is held to the same rule")
        for visible in ["Zoë", "Zoe\u{0308}", "Dee-Ann", "李雷", "Sam 😀", "Sam 👍🏽", "O'Neil", "\u{2764}"] {
            XCTAssertTrue(RoomText.isValidNickname(visible), "refused \(visible)")
        }
    }

    func testHashAndFingerprintAreInvariantUnderEntryOrder() throws {
        let entries = try threeEntries()
        let a = try Roster(session: session, label: "l", entries: entries)
        let b = try Roster(session: session, label: "l", entries: entries.reversed())
        let c = try Roster(session: session, label: "l", entries: [entries[1], entries[0], entries[2]])
        XCTAssertEqual(a.rosterHash, b.rosterHash)
        XCTAssertEqual(a.rosterHash, c.rosterHash)
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a.fingerprint, c.fingerprint)
        XCTAssertEqual(a.rosterHash.count, 32)
    }

    func testFingerprintBindsLabelSessionSizeAndEveryKey() throws {
        let entries = try threeEntries()
        let base = try Roster(session: session, label: "Salary", entries: entries)
        let otherLabel = try Roster(session: session, label: "Bonus", entries: entries)
        XCTAssertEqual(base.rosterHash, otherLabel.rosterHash, "the roster hash does not cover the label")
        XCTAssertNotEqual(base.fingerprint, otherLabel.fingerprint, "the fingerprint does")
        let otherSession = try Roster(session: SessionID.random(), label: "Salary", entries: entries)
        XCTAssertNotEqual(base.rosterHash, otherSession.rosterHash)
        XCTAssertNotEqual(base.fingerprint, otherSession.fingerprint)
        let bigger = try Roster(session: session, label: "Salary", entries: entries + [try makeEntry(4, 14)])
        XCTAssertNotEqual(base.rosterHash, bigger.rosterHash)
        XCTAssertNotEqual(base.fingerprint, bigger.fingerprint)
        var swappedMask = entries
        swappedMask[0] = RosterEntry(verifyingKey: entries[0].verifyingKey, maskPublicKey: try makeEntry(9, 99).maskPublicKey, nickname: entries[0].nickname)
        let maskChanged = try Roster(session: session, label: "Salary", entries: swappedMask)
        XCTAssertNotEqual(base.rosterHash, maskChanged.rosterHash, "a substituted mask key must change the roster")
        XCTAssertNotEqual(base.fingerprint, maskChanged.fingerprint)
        var renamed = entries
        renamed[0] = RosterEntry(verifyingKey: entries[0].verifyingKey, maskPublicKey: entries[0].maskPublicKey, nickname: "someone else")
        let nickChanged = try Roster(session: session, label: "Salary", entries: renamed)
        XCTAssertNotEqual(base.rosterHash, nickChanged.rosterHash, "a nickname shown differently on two phones must change the code")
    }

    func testFingerprintFormatIsCrockfordXXXXdashXXXX() throws {
        let roster = try Roster(session: session, label: "l", entries: try threeEntries())
        let code = roster.fingerprint.code
        XCTAssertEqual(code.count, 9)
        XCTAssertEqual(code[code.index(code.startIndex, offsetBy: 4)], "-")
        let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ-")
        XCTAssertTrue(code.allSatisfy { allowed.contains($0) }, code)
        XCTAssertFalse(code.contains(where: { "ILOU".contains($0) }))
    }

    func testCrockfordEncodingPins() {
        XCTAssertEqual(RoomFingerprint.crockford(Data(hexString: "0000000000")), "0000-0000")
        XCTAssertEqual(RoomFingerprint.crockford(Data(hexString: "ffffffffff")), "ZZZZ-ZZZZ")
        XCTAssertEqual(RoomFingerprint.crockford(Data(hexString: "00443214c7")), "0123-4567")
        XCTAssertEqual(RoomFingerprint.crockford(Data(hexString: "4254b635cf")), "89AB-CDEF")
        XCTAssertEqual(RoomFingerprint.crockford(Data(hexString: "8ca74adaff")), "HJKM-NPQZ")
    }

    func testRosterVectorsFromThePythonOracle() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "core_vectors", withExtension: "json", subdirectory: "Fixtures"))
        let vectors = try JSONDecoder().decode(RosterVectors.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(vectors.rosters.count, 3)
        for v in vectors.rosters {
            let entries = try v.entries.map { e in
                RosterEntry(verifyingKey: try SigningKey(rawRepresentation: Data(hexString: e.scalar_hex)).verifyingKey,
                            maskPublicKey: try MaskPrivateKey(rawRepresentation: Data(hexString: e.mask_scalar_hex)).publicKey,
                            nickname: e.nickname)
            }
            let roster = try Roster(session: try XCTUnwrap(SessionID(hex: v.session)), label: v.label, entries: entries)
            XCTAssertEqual(entries.map { roster.label(for: $0.verifyingKey)!.letter }, v.letters, v.label)
            XCTAssertEqual(roster.rosterHash, Data(hexString: v.roster_hash), v.label)
            XCTAssertEqual(roster.fingerprint.code, v.fingerprint, v.label)
        }
    }
}

final class CanonicalMessageTests: XCTestCase {
    func testPinnedCrossLanguageFormat() {
        let message = CanonicalMessage(action: .share, session: "ABCDEF", party: "A", content: "123")
        XCTAssertEqual(message.string, "share|ABCDEF|A|123")
    }

    func testActionNamesAreTheSpecSet() {
        XCTAssertEqual(MessageAction.allCases.map(\.rawValue),
                       ["pubkey", "share", "roomcode_confirm", "result_confirm", "control"])
    }

    func testEveryFieldIsPresentInOrderAndContentMayBeAnything() {
        let message = CanonicalMessage(action: .control, session: "s", party: "host", content: "{\"a\":\"x|y\"}")
        XCTAssertEqual(message.string, "control|s|host|{\"a\":\"x|y\"}")
        XCTAssertEqual(CanonicalMessage(action: .resultConfirm, session: "s", party: "H", content: "").string, "result_confirm|s|H|")
    }
}
