import XCTest
import Foundation
@testable import CravageCore

/// Wire envelope and message-domain limits (PLAN.md "Message domain limits"; SPEC section 3).
/// Everything here happens before the engine sees a message and, for the limits, before any
/// crypto runs.
final class EnvelopeTests: XCTestCase {
    let session = SessionID(hex: String(repeating: "0a", count: 16))!
    let key = SigningKey()

    private func envelope(action: MessageAction = .share, party: String = "A", content: String = "123",
                          key: SigningKey? = nil) -> Envelope {
        Envelope.signed(action: action, session: session, party: party, content: content, key: key ?? self.key)
    }

    private func json(_ envelope: Envelope) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.encoded()) as? [String: Any])
    }

    private func bytes(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Round trip

    func testSignedEnvelopeDecodesAndVerifies() throws {
        let sent = envelope()
        let data = sent.encoded()
        XCTAssertLessThan(data.count, 512)
        let received = try Envelope.decodeAndVerify(data)
        XCTAssertEqual(received.session, session)
        XCTAssertEqual(received.action, .share)
        XCTAssertEqual(received.party, "A")
        XCTAssertEqual(received.content, "123")
        XCTAssertEqual(received.sender, key.verifyingKey)
        XCTAssertEqual(received.canonical.string, "share|" + session.hex + "|A|123")
    }

    func testEncodingIsTheDocumentedFieldSet() throws {
        let object = try json(envelope(action: .roomcodeConfirm, party: "B", content: "abc"))
        XCTAssertEqual(Set(object.keys), ["v", "session", "action", "party", "sender", "content", "sig"])
        XCTAssertEqual(object["v"] as? Int, CravageCore.protocolVersion)
        XCTAssertEqual(object["action"] as? String, "roomcode_confirm")
        XCTAssertEqual(object["session"] as? String, session.hex)
        XCTAssertEqual(object["party"] as? String, "B")
        XCTAssertEqual(object["sender"] as? String, key.verifyingKey.base64)
        XCTAssertEqual(object["content"] as? String, "abc")
        XCTAssertEqual(Data(base64Encoded: object["sig"] as! String)?.count, 64)
    }

    func testEveryActionRoundTrips() throws {
        for action in MessageAction.allCases {
            let received = try Envelope.decodeAndVerify(envelope(action: action).encoded())
            XCTAssertEqual(received.action, action)
        }
    }

    func testUnknownFieldsAreIgnored() throws {
        var object = try json(envelope())
        object["extra"] = ["future": [1, 2, 3]]
        object["note"] = "ignored"
        let received = try Envelope.decodeAndVerify(try bytes(object))
        XCTAssertEqual(received.content, "123")
    }

    // MARK: - Tampering

    func testAnyChangeToSignedFieldsFailsVerification() throws {
        let base = try json(envelope())
        for (field, value) in [("session", String(repeating: "0b", count: 16)), ("action", "pubkey"),
                               ("party", "B"), ("content", "124"), ("content", "")] as [(String, String)] {
            var object = base
            object[field] = value
            XCTAssertThrowsError(try Envelope.decodeAndVerify(try bytes(object)), "\(field) = \(value)") { error in
                XCTAssertEqual(error as? MessageError, .badSignature, "\(field) = \(value)")
            }
        }
    }

    func testSenderSubstitutionFailsVerification() throws {
        var object = try json(envelope())
        object["sender"] = SigningKey().verifyingKey.base64
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try bytes(object))) { error in
            XCTAssertEqual(error as? MessageError, .badSignature)
        }
        var swappedSig = try json(envelope())
        swappedSig["sig"] = try json(envelope(content: "999"))["sig"]
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try bytes(swappedSig))) { error in
            XCTAssertEqual(error as? MessageError, .badSignature)
        }
    }

    // MARK: - Domain limits, checked before any crypto

    func testOversizedEnvelopeIsRejectedBeforeParsing() throws {
        var object = try json(envelope())
        object["content"] = String(repeating: "x", count: MessageDomain.maxEnvelopeBytes)
        object["sig"] = "not even base64"
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try bytes(object))) { error in
            XCTAssertEqual(error as? MessageError, .tooLarge)
        }
        XCTAssertThrowsError(try Envelope.decodeAndVerify(Data(repeating: UInt8(ascii: "{"), count: MessageDomain.maxEnvelopeBytes + 1))) { error in
            XCTAssertEqual(error as? MessageError, .tooLarge)
        }
        // Exactly at the cap is allowed through to parsing.
        let atCap = Data(repeating: UInt8(ascii: " "), count: MessageDomain.maxEnvelopeBytes)
        XCTAssertThrowsError(try Envelope.decodeAndVerify(atCap)) { error in
            XCTAssertEqual(error as? MessageError, .malformed)
        }
    }

    func testDeeplyNestedJSONIsRejectedBeforeParsing() throws {
        let depth = MessageDomain.maxJSONDepth + 1
        let nested = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let text = "{\"v\":1,\"extra\":" + nested + "}"
        XCTAssertThrowsError(try Envelope.decodeAndVerify(Data(text.utf8))) { error in
            XCTAssertEqual(error as? MessageError, .tooDeep)
        }
        // Brackets inside strings do not count as nesting.
        var object = try json(envelope())
        object["content"] = String(repeating: "[{", count: 50) + "\"" + String(repeating: "]", count: 50)
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try bytes(object))) { error in
            XCTAssertEqual(error as? MessageError, .badSignature, "content changed, so only the signature fails")
        }
        let allowed = String(repeating: "[", count: MessageDomain.maxJSONDepth - 1) + String(repeating: "]", count: MessageDomain.maxJSONDepth - 1)
        var okObject = try json(envelope())
        okObject["extra"] = try JSONSerialization.jsonObject(with: Data(allowed.utf8))
        XCTAssertNoThrow(try Envelope.decodeAndVerify(try bytes(okObject)))
    }

    func testUnsupportedVersionIsReportedEvenWhenTheRestIsUnreadable() throws {
        for text in ["{\"v\":2}", "{\"v\":2,\"shape\":{\"totally\":\"different\"}}", "{\"v\":0}", "{\"v\":-1}", "{\"v\":99999}"] {
            XCTAssertThrowsError(try Envelope.decodeAndVerify(Data(text.utf8)), text) { error in
                guard case .unsupportedVersion(let v)? = error as? MessageError else { return XCTFail("\(text): \(error)") }
                XCTAssertNotEqual(v, CravageCore.protocolVersion)
            }
        }
    }

    func testMalformedInputsAreMalformedNotCrashes() throws {
        let valid = try json(envelope())
        var cases: [Data] = [Data(), Data("null".utf8), Data("[]".utf8), Data("{}".utf8), Data("\"v\"".utf8),
                             Data("{\"v\":\"1\"}".utf8), Data("{\"v\":1.5}".utf8), Data("{\"v\":1}".utf8),
                             Data("not json".utf8), Data([0xff, 0xfe, 0x00]), Data("{\"v\":1,".utf8)]
        for field in ["session", "action", "party", "sender", "content", "sig"] {
            var missing = valid
            missing.removeValue(forKey: field)
            cases.append(try bytes(missing))
            var wrongType = valid
            wrongType[field] = 42
            cases.append(try bytes(wrongType))
            var null = valid
            null[field] = NSNull()
            cases.append(try bytes(null))
        }
        for (field, value) in [("session", "ABCD"), ("session", ""), ("sender", "AAAA"), ("sender", ""),
                               ("sig", "AAAA"), ("sig", ""), ("sig", "!!!!"), ("action", "confirm"), ("action", "")] {
            var bad = valid
            bad[field] = value
            cases.append(try bytes(bad))
        }
        for data in cases {
            XCTAssertThrowsError(try Envelope.decodeAndVerify(data), String(decoding: data.prefix(60), as: UTF8.self)) { error in
                guard let e = error as? MessageError else { return XCTFail("\(error)") }
                switch e {
                case .malformed, .unknownAction: break
                default: XCTFail("\(e) for \(String(decoding: data.prefix(60), as: UTF8.self))")
                }
            }
        }
    }

    func testUnknownActionIsItsOwnError() throws {
        var object = try json(envelope())
        object["action"] = "confirm"
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try bytes(object))) { error in
            XCTAssertEqual(error as? MessageError, .unknownAction)
        }
    }

    func testPartyAndContentMayCarryAnyText() throws {
        let received = try Envelope.decodeAndVerify(envelope(party: key.verifyingKey.base64, content: "a|b,c \u{00a3} \u{2603} \"q\" \\ \n").encoded())
        XCTAssertEqual(received.party, key.verifyingKey.base64)
        XCTAssertEqual(received.content, "a|b,c \u{00a3} \u{2603} \"q\" \\ \n")
    }

    // MARK: - Fuzz

    func testRandomCorruptionNeverCrashesAndNeverVerifiesAChangedMessage() throws {
        let original = envelope()
        let data = original.encoded()
        var accepted = 0
        for _ in 0..<3000 {
            var mutated = data
            switch Int.random(in: 0..<5) {
            case 0:
                let index = Int.random(in: 0..<mutated.count)
                mutated[index] = UInt8.random(in: .min ... .max)
            case 1:
                mutated = mutated.prefix(Int.random(in: 0..<mutated.count))
            case 2:
                let index = Int.random(in: 0...mutated.count)
                mutated.insert(UInt8.random(in: .min ... .max), at: index)
            case 3:
                let index = Int.random(in: 0..<mutated.count)
                mutated.remove(at: index)
            default:
                for _ in 0..<Int.random(in: 1...8) {
                    let index = Int.random(in: 0..<mutated.count)
                    mutated[index] = [UInt8(ascii: "\""), UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "\\"), 0x00, 0xff].randomElement()!
                }
            }
            if let received = try? Envelope.decodeAndVerify(mutated) {
                accepted += 1
                // Whatever survived must be the original message, not a variant of it.
                XCTAssertEqual(received.session, session)
                XCTAssertEqual(received.action, .share)
                XCTAssertEqual(received.party, "A")
                XCTAssertEqual(received.content, "123")
                XCTAssertEqual(received.sender, key.verifyingKey)
            }
        }
        XCTAssertLessThan(accepted, 3000)
    }
}

final class RosterBindingTests: XCTestCase {
    func testPostLockMessagesSignTheRosterHashIntoTheSession() throws {
        let key = SigningKey()
        let session = SessionID.random()
        let hash = Digest.sha256(Data("roster".utf8))
        let data = Envelope.signed(action: .share, session: session, rosterHash: hash, party: "A", content: "5", key: key).encoded()
        let received = try Envelope.decodeAndVerify(data)
        XCTAssertEqual(received.session, session)
        XCTAssertEqual(received.rosterHash, hash)
        XCTAssertEqual(received.boundSession, session.hex + "." + Hex.encode(hash))
        XCTAssertEqual(received.canonical.string, "share|" + session.hex + "." + Hex.encode(hash) + "|A|5")

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["session"] = session.hex + "." + Hex.encode(Digest.sha256(Data("other".utf8)))
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? MessageError, .badSignature)
        }
        object["session"] = session.hex
        XCTAssertThrowsError(try Envelope.decodeAndVerify(try JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? MessageError, .badSignature, "stripping the binding breaks the signature")
        }
        for bad in [session.hex + ".", session.hex + "." + Hex.encode(hash).uppercased(), session.hex + "." + Hex.encode(hash) + ".00",
                    session.hex + "." + String(Hex.encode(hash).dropLast(2)), "." + Hex.encode(hash)] {
            object["session"] = bad
            XCTAssertThrowsError(try Envelope.decodeAndVerify(try JSONSerialization.data(withJSONObject: object)), bad) {
                XCTAssertEqual($0 as? MessageError, .malformed, bad)
            }
        }
    }

    func testHexIsLowercaseAndStrict() {
        XCTAssertEqual(Hex.encode(Data([0x00, 0xab, 0xff])), "00abff")
        XCTAssertEqual(Hex.decode("00abff"), Data([0x00, 0xab, 0xff]))
        XCTAssertNil(Hex.decode("00ABFF"))
        XCTAssertNil(Hex.decode("abc"))
        XCTAssertNil(Hex.decode("zz"))
        XCTAssertEqual(Hex.decode(""), Data())
    }
}
