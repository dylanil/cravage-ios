import XCTest
import Foundation
@testable import CravageCore

/// The largest messages the protocol can produce must fit one frame (MessageDomain.maxEnvelopeBytes),
/// or the transport could not carry them.
final class WorstCaseSizeTests: XCTestCase {
    func testLargestRosterAndWelcomeFitOneEnvelope() throws {
        // Quotes and backslashes are legal in nicknames and labels and grow the most under JSON
        // escaping, which happens twice: once in the control content, once in the envelope.
        let worstNick = String(repeating: "\"", count: RoomText.maxNicknameBytes)
        let worstLabel = String(repeating: "\\", count: RoomText.maxLabelBytes)
        XCTAssertTrue(RoomText.isValidNickname(worstNick))
        XCTAssertTrue(RoomText.isValidLabel(worstLabel))
        let session = SessionID.random()
        let nonce = Wire.randomNonce()
        var entries: [Wire.SignedHello] = []
        for _ in 0..<Roster.maximumSize {
            let key = SigningKey(), mask = MaskPrivateKey()
            let hello = Wire.Hello(mask: mask.publicKey, nonce: nonce, nickname: worstNick)
            let sig = key.sign(CanonicalMessage(action: .pubkey, session: session.hex, party: key.verifyingKey.base64, content: hello.content).string)
            entries.append(Wire.SignedHello(vk: key.verifyingKey.base64, mask: mask.publicKey.base64, nick: worstNick, sig: sig.base64))
        }
        let host = SigningKey()
        let roster = Envelope.signed(action: .control, session: session, party: Wire.hostParty,
                                     content: Wire.encode(.roster(entries)), key: host).encoded()
        let welcome = Envelope.signed(action: .control, session: session, party: Wire.hostParty,
                                      content: Wire.encode(.welcome(nonce: nonce, label: worstLabel, size: 8)), key: host).encoded()
        print("WORST roster bytes:", roster.count, "welcome bytes:", welcome.count)
        XCTAssertLessThanOrEqual(roster.count, MessageDomain.maxEnvelopeBytes)
        XCTAssertLessThanOrEqual(welcome.count, MessageDomain.maxEnvelopeBytes)
        XCTAssertNoThrow(try Envelope.decodeAndVerify(roster))
    }
}
