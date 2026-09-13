import XCTest
import Foundation
@testable import CravageCore

/// Python-oracle fixture produced by Tools/gen_core_fixtures.py with the same `cryptography` calls
/// verify_round.py uses. Arithmetic vectors were computed on unbounded integers mod 2^64.
struct CoreVectors: Decodable {
    struct Round: Decodable {
        let parties: [String]
        let figures: [String: String]
        let masks: [String: String]
        let shares: [String: String]
        let sum: String
    }
    struct WrappingAdd: Decodable { let a: String; let b: String; let sum: String; let product: String }
    struct SignatureVector: Decodable {
        let private_scalar_hex: String
        let vk: String
        let message: String
        let signature: String
    }
    struct MaskVector: Decodable {
        let lo_scalar_hex: String
        let hi_scalar_hex: String
        let lo: String
        let hi: String
        let mask: String
    }
    struct DigestVector: Decodable { let input: String; let sha256: String }

    let rounds: [Round]
    let wrapping_adds: [WrappingAdd]
    let signatures: [SignatureVector]
    let masks: [MaskVector]
    let digests: [DigestVector]

    static func load() throws -> CoreVectors {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "core_vectors", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try JSONDecoder().decode(CoreVectors.self, from: Data(contentsOf: url))
    }
}

extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

final class PartyLabelTests: XCTestCase {
    func testOnlyTheEightLettersAreLabels() {
        XCTAssertEqual(PartyLabel.all.map(\.letter), ["A", "B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(PartyLabel.all.count, FixedPoint.maxParties)
        for bad in ["", "I", "a", "AB", " A", "Z", "\u{0391}", "1"] {
            XCTAssertNil(PartyLabel(bad), bad)
        }
        XCTAssertEqual(PartyLabel("C")?.letter, "C")
    }

    func testLabelsOrderBytewise() {
        XCTAssertLessThan(PartyLabel("A")!, PartyLabel("B")!)
        XCTAssertLessThan(PartyLabel("G")!, PartyLabel("H")!)
        XCTAssertEqual(PartyLabel.all.sorted(), PartyLabel.all)
        XCTAssertEqual(PartyLabel.all.reversed().sorted(), PartyLabel.all)
    }
}

final class WraparoundTests: XCTestCase {
    func testMaskSignPins() {
        XCTAssertEqual(Wraparound.maskSign(PartyLabel("A")!, PartyLabel("B")!), 1)
        XCTAssertEqual(Wraparound.maskSign(PartyLabel("B")!, PartyLabel("A")!), -1)
        XCTAssertEqual(Wraparound.maskSign(PartyLabel("H")!, PartyLabel("G")!), -1)
        XCTAssertEqual(Wraparound.maskSign(PartyLabel("A")!, PartyLabel("H")!), 1)
    }

    func testSignedInt64BigEndianPin() {
        XCTAssertEqual(Wraparound.signedInt64BigEndian(Data(hexString: "8000000000000000")), Int64.min)
        XCTAssertEqual(Wraparound.signedInt64BigEndian(Data(hexString: "7fffffffffffffff")), Int64.max)
        XCTAssertEqual(Wraparound.signedInt64BigEndian(Data(hexString: "ffffffffffffffff")), -1)
        XCTAssertEqual(Wraparound.signedInt64BigEndian(Data(hexString: "0000000000000001")), 1)
        XCTAssertEqual(Wraparound.signedInt64BigEndian(Data(hexString: "0000000000000000")), 0)
    }

    func testWrappingAddAndMultiplyMatchThePythonOracle() throws {
        let vectors = try CoreVectors.load()
        XCTAssertGreaterThan(vectors.wrapping_adds.count, 200)
        for v in vectors.wrapping_adds {
            let a = Int64(v.a)!, b = Int64(v.b)!
            XCTAssertEqual(Wraparound.sum([a, b]), Int64(v.sum)!, "\(v.a) + \(v.b)")
            XCTAssertEqual(a &* b, Int64(v.product)!, "\(v.a) x \(v.b)")
        }
    }

    func testSharesAndSumsMatchThePythonOracleForThreeToEightParties() throws {
        let vectors = try CoreVectors.load()
        XCTAssertGreaterThanOrEqual(vectors.rounds.count, 72)
        var seenSizes = Set<Int>()
        for round in vectors.rounds {
            let parties = round.parties.map { PartyLabel($0)! }
            seenSizes.insert(parties.count)
            var shares: [Int64] = []
            for me in parties {
                var pairMasks: [PartyLabel: Int64] = [:]
                for other in parties where other != me {
                    let key = min(me, other).letter + max(me, other).letter
                    pairMasks[other] = Int64(round.masks[key]!)!
                }
                let share = Wraparound.share(figure: Int64(round.figures[me.letter]!)!, me: me, pairMasks: pairMasks)
                XCTAssertEqual(share, Int64(round.shares[me.letter]!)!, "share of \(me.letter) in \(round.parties)")
                shares.append(share)
            }
            XCTAssertEqual(Wraparound.sum(shares), Int64(round.sum)!, "sum for \(round.parties)")
        }
        XCTAssertEqual(seenSizes, Set(3...8))
    }

    func testMasksCancelForRandomFiguresAndUniformMasks() {
        for n in 3...8 {
            let parties = Array(PartyLabel.all.prefix(n))
            let figures = parties.map { _ in
                Int64.random(in: -FixedPoint.maxMagnitude...FixedPoint.maxMagnitude)
            }
            var masks: [String: Int64] = [:]
            for (i, lo) in parties.enumerated() {
                for hi in parties[(i + 1)...] { masks[lo.letter + hi.letter] = Int64(bitPattern: UInt64.random(in: .min ... .max)) }
            }
            let shares = parties.enumerated().map { index, me -> Int64 in
                var pairMasks: [PartyLabel: Int64] = [:]
                for other in parties where other != me {
                    pairMasks[other] = masks[min(me, other).letter + max(me, other).letter]!
                }
                return Wraparound.share(figure: figures[index], me: me, pairMasks: pairMasks)
            }
            let expected = figures.reduce(Int64(0)) { $0 &+ $1 }
            XCTAssertEqual(Wraparound.sum(shares), expected, "N=\(n)")
        }
    }

    func testShareWithNoMasksIsTheFigureAndNeverTraps() {
        XCTAssertEqual(Wraparound.share(figure: 42, me: PartyLabel("A")!, pairMasks: [:]), 42)
        XCTAssertEqual(Wraparound.share(figure: Int64.max, me: PartyLabel("A")!, pairMasks: [PartyLabel("B")!: 1]), Int64.min)
        XCTAssertEqual(Wraparound.share(figure: Int64.min, me: PartyLabel("B")!, pairMasks: [PartyLabel("A")!: 1]), Int64.max)
        XCTAssertEqual(Wraparound.share(figure: 0, me: PartyLabel("B")!, pairMasks: [PartyLabel("A")!: Int64.min]), Int64.min)
        XCTAssertEqual(Wraparound.sum([]), 0)
        XCTAssertEqual(Wraparound.sum([Int64.max, Int64.max]), -2)
    }
}

final class ShareStringTests: XCTestCase {
    func testFormatIsPlainDecimalAndRoundTrips() throws {
        for value: Int64 in [0, 1, -1, 123, -123, Int64.max, Int64.min, 5_107_112_043_798_890_199] {
            let text = ShareString.format(value)
            XCTAssertEqual(try ShareString.parse(text), value, text)
        }
        XCTAssertEqual(ShareString.format(Int64.min), "-9223372036854775808")
        XCTAssertEqual(ShareString.format(-5), "-5")
    }

    func testParseAcceptsOnlyCanonicalInt64Strings() throws {
        XCTAssertEqual(try ShareString.parse("9223372036854775807"), Int64.max)
        XCTAssertEqual(try ShareString.parse("-9223372036854775808"), Int64.min)
        XCTAssertEqual(try ShareString.parse("0"), 0)
        for bad in ["", "-", "+1", " 1", "1 ", "1.0", "1e3", "0x1", "١", "abc", "--1", "1-", "\n1"] {
            XCTAssertThrowsError(try ShareString.parse(bad), bad.debugDescription) { error in
                XCTAssertEqual(error as? ShareStringError, .malformed, bad.debugDescription)
            }
        }
        // Non-canonical spellings of a valid value are rejected too, so first-write-wins
        // comparisons on the string are the same as comparisons on the value.
        for bad in ["01", "-0", "-01", "00"] {
            XCTAssertThrowsError(try ShareString.parse(bad), bad.debugDescription) { error in
                XCTAssertEqual(error as? ShareStringError, .malformed, bad.debugDescription)
            }
        }
        for bad in ["9223372036854775808", "-9223372036854775809", "18446744073709551616",
                    "99999999999999999999", "123456789012345678901"] {
            XCTAssertThrowsError(try ShareString.parse(bad), bad.debugDescription) { error in
                XCTAssertEqual(error as? ShareStringError, .outOfRange, bad.debugDescription)
            }
        }
    }
}

final class DigestTests: XCTestCase {
    func testSHA256PinsFromTheSMPCContractVector() throws {
        XCTAssertEqual(Digest.sha256Hex(Data("SMPC-contract-vector v1".utf8)),
                       "8daf9b4afa1031808e15d1756a5b611089f9866f96890ec45e0d08ca5b081529")
        let multiblock = "SMPC-contract-vector multiblock v1: this string is deliberately " +
            "longer than sixty-four bytes so SHA-256 spans multiple blocks."
        XCTAssertEqual(Digest.sha256Hex(Data(multiblock.utf8)),
                       "8fb355047678afde0e3f4844bb2688f740b077c897585343fc73b54c0af7111b")
        for v in try CoreVectors.load().digests {
            XCTAssertEqual(Digest.sha256Hex(Data(v.input.utf8)), v.sha256, v.input)
            XCTAssertEqual(Digest.sha256(Data(v.input.utf8)), Data(hexString: v.sha256))
        }
    }
}

final class SigningTests: XCTestCase {
    func testPythonSignaturesVerifyUnderTheStatedKeys() throws {
        let vectors = try CoreVectors.load()
        XCTAssertGreaterThanOrEqual(vectors.signatures.count, 5)
        for v in vectors.signatures {
            let vk = try VerifyingKey(base64: v.vk)
            let signature = try Signature(base64: v.signature)
            XCTAssertTrue(vk.verify(signature, message: v.message), v.message)
            // The scalar reproduces the same public key, so Swift and Python agree on encoding.
            let sk = try SigningKey(rawRepresentation: Data(hexString: v.private_scalar_hex))
            XCTAssertEqual(sk.verifyingKey, vk, v.message)
            XCTAssertEqual(sk.verifyingKey.base64, v.vk)
        }
    }

    func testSwiftSignaturesVerifyAndTamperingFails() throws {
        let key = SigningKey()
        let message = "share|ABCDEF|A|123"
        let signature = key.sign(message)
        XCTAssertEqual(signature.raw.count, 64)
        XCTAssertTrue(key.verifyingKey.verify(signature, message: message))
        XCTAssertFalse(key.verifyingKey.verify(signature, message: "share|ABCDEF|A|124"))
        XCTAssertFalse(key.verifyingKey.verify(signature, message: "share|ABCDEF|B|123"))
        XCTAssertFalse(key.verifyingKey.verify(signature, message: ""))
        XCTAssertFalse(SigningKey().verifyingKey.verify(signature, message: message), "wrong key")
        var tampered = signature.raw
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertFalse(key.verifyingKey.verify(try Signature(raw: tampered), message: message))
        var flippedR = signature.raw
        flippedR[0] ^= 0x80
        XCTAssertFalse(key.verifyingKey.verify(try Signature(raw: flippedR), message: message))
    }

    func testEncodingsAreTheWebCryptoRawForms() throws {
        let key = SigningKey()
        XCTAssertEqual(key.verifyingKey.x963.count, 65)
        XCTAssertEqual(key.verifyingKey.x963.first, 0x04)
        XCTAssertEqual(try VerifyingKey(base64: key.verifyingKey.base64), key.verifyingKey)
        let signature = key.sign("m")
        XCTAssertEqual(try Signature(base64: signature.base64), signature)
        XCTAssertEqual(Data(base64Encoded: signature.base64)?.count, 64)
    }

    func testMalformedKeysAndSignaturesAreRejected() {
        for bad in ["", "not base64!", "AA==", String(repeating: "A", count: 88),
                    Data(repeating: 0x04, count: 65).base64EncodedString(),
                    Data(repeating: 0x02, count: 33).base64EncodedString()] {
            XCTAssertThrowsError(try VerifyingKey(base64: bad), bad)
        }
        for bad in ["", "AA==", Data(repeating: 0, count: 63).base64EncodedString(),
                    Data(repeating: 0, count: 65).base64EncodedString(), "*&^%"] {
            XCTAssertThrowsError(try Signature(base64: bad), bad)
        }
        XCTAssertThrowsError(try SigningKey(rawRepresentation: Data(repeating: 0, count: 32)))
        XCTAssertThrowsError(try SigningKey(rawRepresentation: Data(repeating: 1, count: 31)))
    }

    /// Letters A..H are assigned by bytewise sort of verifying keys (PLAN, PartyLabel), so the
    /// key type must order by its x963 bytes and nothing else.
    func testVerifyingKeysOrderBytewiseForLetterAssignment() throws {
        let keys = (0..<8).map { _ in SigningKey().verifyingKey }
        let sorted = keys.sorted()
        for pair in zip(sorted, sorted.dropFirst()) {
            XCTAssertTrue(Array(pair.0.x963).lexicographicallyPrecedes(Array(pair.1.x963)))
            XCTAssertNotEqual(pair.0, pair.1)
        }
        XCTAssertEqual(Set(sorted), Set(keys))
        XCTAssertFalse(sorted[0] < sorted[0])
    }
}

final class MaskTests: XCTestCase {
    func testPinnedMaskVectorIsSymmetric() throws {
        let k1 = try MaskPrivateKey(rawRepresentation: Data(hexString: String(repeating: "11", count: 32)))
        let k2 = try MaskPrivateKey(rawRepresentation: Data(hexString: String(repeating: "22", count: 32)))
        let a = PartyLabel("A")!, b = PartyLabel("B")!
        XCTAssertEqual(k1.mask(with: k2.publicKey, lo: a, hi: b), 5_107_112_043_798_890_199)
        XCTAssertEqual(k2.mask(with: k1.publicKey, lo: a, hi: b), 5_107_112_043_798_890_199)
        XCTAssertNotEqual(k1.mask(with: k2.publicKey, lo: b, hi: a), 5_107_112_043_798_890_199,
                          "the info string is order-sensitive")
        XCTAssertNotEqual(k1.mask(with: k2.publicKey, lo: a, hi: PartyLabel("C")!), 5_107_112_043_798_890_199)
    }

    func testMaskVectorsFromThePythonOracle() throws {
        let vectors = try CoreVectors.load()
        XCTAssertGreaterThanOrEqual(vectors.masks.count, 4)
        for v in vectors.masks {
            let lo = try MaskPrivateKey(rawRepresentation: Data(hexString: v.lo_scalar_hex))
            let hi = try MaskPrivateKey(rawRepresentation: Data(hexString: v.hi_scalar_hex))
            let expected = Int64(v.mask)!
            XCTAssertEqual(lo.mask(with: hi.publicKey, lo: PartyLabel(v.lo)!, hi: PartyLabel(v.hi)!), expected)
            XCTAssertEqual(hi.mask(with: lo.publicKey, lo: PartyLabel(v.lo)!, hi: PartyLabel(v.hi)!), expected)
        }
    }

    func testFreshKeysAreDistinctAndPublicKeysRoundTripBase64() throws {
        let k1 = MaskPrivateKey(), k2 = MaskPrivateKey()
        XCTAssertNotEqual(k1.publicKey, k2.publicKey)
        XCTAssertEqual(k1.publicKey.x963.count, 65)
        XCTAssertEqual(try MaskPublicKey(base64: k1.publicKey.base64), k1.publicKey)
        for bad in ["", "AA==", Data(repeating: 0x04, count: 65).base64EncodedString()] {
            XCTAssertThrowsError(try MaskPublicKey(base64: bad), bad)
        }
        // A signing key's bytes are not accepted where a mask key is expected and vice versa is
        // only prevented by type: the two are distinct types with no conversion.
        XCTAssertEqual(k1.mask(with: k2.publicKey, lo: PartyLabel("A")!, hi: PartyLabel("B")!),
                       k2.mask(with: k1.publicKey, lo: PartyLabel("A")!, hi: PartyLabel("B")!))
    }
}
