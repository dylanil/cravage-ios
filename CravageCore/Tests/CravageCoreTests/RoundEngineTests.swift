import XCTest
import Foundation
@testable import CravageCore

/// RoundEngine through the real message route (PLAN.md CravageCore invariants 1-10, SPEC section 3
/// invariants 1-13). Every negative test delivers bytes to `handle(.received)`; nothing pokes
/// engine state directly.
final class RoundEngineTests: XCTestCase {

    // MARK: - Happy paths

    func testThreePartyRoundAgreesOnTheExactAverage() throws {
        let bus = StarBus.completed(figures: [10_000_000, 20_000_000, 30_000_000])
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 3))
        for engine in bus.engines {
            XCTAssertEqual(engine.sum, 60_000_000)
            XCTAssertEqual(engine.average, "20")
            XCTAssertEqual(engine.roster?.fingerprint, bus.host.roster?.fingerprint)
            XCTAssertNil(engine.nextDeadline)
            XCTAssertNil(engine.maskKey, "mask keys are discarded at round end")
            XCTAssertNil(engine.frozenFigure, "figures are cleared at round end")
        }
        XCTAssertEqual(Set(bus.engines.compactMap(\.myLetter)), Set(PartyLabel.all.prefix(3)))
        XCTAssertTrue(bus.rejections.isEmpty, "\(bus.rejections)")
    }

    func testEightPartyRoundAtTheDomainEdgeIsExact() throws {
        let figures = Array(repeating: FixedPoint.maxMagnitude, count: 8)
        let bus = StarBus.completed(figures: figures)
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 8))
        for engine in bus.engines {
            XCTAssertEqual(engine.sum, 7_999_999_999_999_999_992)
            XCTAssertEqual(engine.average, "1000000000000")
        }
        let record = try XCTUnwrap(bus.engines[3].record)
        XCTAssertEqual(record.parties.count, 8)
        XCTAssertEqual(record.shares.count, 8)
        XCTAssertEqual(record.resultConfirmSignatures.count, 8)
        for party in record.parties {
            let share = try XCTUnwrap(record.shares[party.label])
            let signature = try XCTUnwrap(record.shareSignatures[party.label])
            let canonical = CanonicalMessage(action: .share, session: record.boundSession, party: party.label.letter, content: share)
            XCTAssertTrue(party.verifyingKey.verify(signature, message: canonical.string))
        }
    }

    func testNegativeAndMixedFiguresForEveryRoomSize() {
        for n in 3...8 {
            var figures: [Int64] = []
            for i in 0..<n {
                let index = Int64(i)
                figures.append(i % 2 == 0 ? -1_500_000 * (index + 1) : 2_250_000 * index)
            }
            let bus = StarBus.completed(figures: figures)
            XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: n), "N=\(n)")
            XCTAssertEqual(bus.host.sum, figures.reduce(0, +), "N=\(n)")
            XCTAssertEqual(bus.engines.last?.average, FixedPoint.formatAverageFixed(figures.reduce(0, +), count: n))
        }
    }

    func testLobbyShowsHowManyOtherPhonesAreExpected() {
        let bus = StarBus.locked(nodes: 5)
        for engine in bus.engines {
            XCTAssertEqual(engine.phase, .confirming)
            XCTAssertEqual(engine.otherPhonesExpected, 4, "SPEC invariant 12")
        }
    }

    // MARK: - Invariant 1: control only from the host, bound to this session

    func testRosterFromANonHostIsRejected() throws {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        let impostor = SigningKey()
        let joiner = bus.engines[1]
        let fake = Envelope.signed(action: .control, session: joiner.session!, party: Wire.hostParty,
                                   content: Wire.encode(.abort(.timeout)), key: impostor).encoded()
        bus.deliver(1, .received(fake, from: .host))
        XCTAssertEqual(joiner.phase, .lobby)
        XCTAssertEqual(bus.rejections[1], [.notFromHost])

        // A joiner cannot send control to the host either.
        let fromJoiner = Envelope.signed(action: .control, session: bus.host.session!, party: Wire.hostParty,
                                         content: Wire.encode(.abort(.timeout)), key: joiner.signingKey!).encoded()
        bus.deliver(0, .received(fromJoiner, from: PeerID(1)))
        XCTAssertEqual(bus.host.phase, .lobby)
        XCTAssertEqual(bus.rejections[0], [.notFromHost])
    }

    func testControlFromAnotherSessionIsRejected() {
        let bus = StarBus.locked(nodes: 3)
        let otherSession = SessionID.random()
        let stale = Envelope.signed(action: .control, session: otherSession, party: Wire.hostParty,
                                    content: Wire.encode(.abort(.timeout)), key: bus.host.signingKey!).encoded()
        bus.deliver(2, .received(stale, from: .host))
        XCTAssertEqual(bus.engines[2].phase, .confirming)
        XCTAssertEqual(bus.rejections[2], [.wrongSession])
    }

    // MARK: - Invariant 2: signed hello, proof of possession, duplicate keys

    func testHelloMustCarryTheHostNonceAndBeSelfSigned() throws {
        let bus = StarBus.lobby(nodes: 3)
        let session = bus.host.session!
        let key = SigningKey(), mask = MaskPrivateKey()
        let wrongNonce = Wire.Hello(mask: mask.publicKey, nonce: Wire.randomNonce(), nickname: "Eve")
        bus.connected.insert(9)
        bus.deliver(0, .peerConnected(PeerID(9)))
        let bad = Envelope.signed(action: .pubkey, session: session, party: key.verifyingKey.base64,
                                  content: wrongNonce.content, key: key).encoded()
        bus.deliver(0, .received(bad, from: PeerID(9)))
        XCTAssertEqual(bus.rejections[0]?.last, .invalidContent)

        // Signed by one key while claiming another: the party field must be the sender.
        let other = SigningKey()
        let good = Wire.Hello(mask: mask.publicKey, nonce: bus.host.nonce!, nickname: "Eve")
        let claimed = Envelope.signed(action: .pubkey, session: session, party: other.verifyingKey.base64,
                                      content: good.content, key: key).encoded()
        bus.deliver(0, .received(claimed, from: PeerID(9)))
        XCTAssertEqual(bus.rejections[0]?.last, .unknownSender)
        XCTAssertEqual(bus.host.pendingJoiners.count, 2)
    }

    func testDuplicateMaskKeyOrIdentityKeyIsRejected() throws {
        let bus = StarBus.lobby(nodes: 3)
        let victimMask = try XCTUnwrap(Wire.Hello.parse(bus.hello(of: 1))).mask
        let key = SigningKey()
        let copied = Wire.Hello(mask: victimMask, nonce: bus.host.nonce!, nickname: "Copy")
        bus.connected.insert(7)
        bus.deliver(0, .peerConnected(PeerID(7)))
        bus.deliver(0, .received(Envelope.signed(action: .pubkey, session: bus.host.session!, party: key.verifyingKey.base64,
                                                 content: copied.content, key: key).encoded(), from: PeerID(7)))
        XCTAssertEqual(bus.rejections[0]?.last, .duplicateKey)

        // Replaying joiner 1's own hello from another connection.
        let replay = try XCTUnwrap(bus.sent.first { $0.from == 1 }).data
        bus.deliver(0, .received(replay, from: PeerID(7)))
        XCTAssertEqual(bus.rejections[0]?.last, .duplicateKey)
        XCTAssertEqual(bus.host.pendingJoiners.count, 2)
    }

    func testJoinerRejectsARosterThatAltersItsOwnEntry() throws {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        let joiner = bus.engines[2]
        let host = bus.host
        // Build the roster the host would send, but swap joiner 2's mask key for one the host holds.
        var entries = host.signedHellosForTesting()
        let index = try XCTUnwrap(entries.firstIndex { $0.vk == joiner.signingKey!.verifyingKey.base64 })
        entries[index] = Wire.SignedHello(vk: entries[index].vk, mask: MaskPrivateKey().publicKey.base64,
                                          nick: entries[index].nick, sig: entries[index].sig)
        let roster = Envelope.signed(action: .control, session: host.session!, party: Wire.hostParty,
                                     content: Wire.encode(.roster(entries)), key: host.signingKey!).encoded()
        bus.deliver(2, .received(roster, from: .host))
        XCTAssertEqual(joiner.phase, .failed(.invalidRoster))
        XCTAssertNil(joiner.roster)
    }

    func testJoinerRejectsARosterWithoutItself() throws {
        let bus = StarBus.lobby(nodes: 4, entitled: true)
        bus.admitAll()
        let host = bus.host
        let entries = host.signedHellosForTesting().filter { $0.vk != bus.engines[3].signingKey!.verifyingKey.base64 }
        let roster = Envelope.signed(action: .control, session: host.session!, party: Wire.hostParty,
                                     content: Wire.encode(.roster(entries)), key: host.signingKey!).encoded()
        bus.deliver(3, .received(roster, from: .host))
        XCTAssertEqual(bus.engines[3].phase, .failed(.invalidRoster))
    }

    // MARK: - Invariant 3: confirmation barrier

    func testNoShareLeavesAnyPhoneUntilEveryoneConfirmed() {
        let bus = StarBus.locked(nodes: 4)
        bus.submit([0: 1_000_000, 1: 2_000_000, 2: 3_000_000, 3: 4_000_000])
        XCTAssertFalse(bus.sentAny(.share))
        bus.confirm([0, 1, 2])
        XCTAssertFalse(bus.sentAny(.share), "three of four confirmed is not enough")
        XCTAssertEqual(bus.phases(), Array(repeating: .confirming, count: 4))
        bus.confirm([3])
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 4))
        XCTAssertEqual(bus.host.sum, 10_000_000)
    }

    func testLocalConfirmIsRequiredEvenWhenAllOthersConfirmed() {
        let bus = StarBus.locked(nodes: 3)
        bus.submit([0: 1, 1: 2, 2: 3])
        bus.confirm([0, 1])
        XCTAssertTrue(bus.originated(by: 2, .share).isEmpty)
        XCTAssertTrue(bus.originated(by: 0, .share).isEmpty, "host still waits for node 2's confirm")
        XCTAssertTrue(bus.originated(by: 1, .share).isEmpty)
        bus.advance(ms: Deadlines.forTests.confirmingMs)
        XCTAssertEqual(bus.phases(), Array(repeating: .failed(.timeout(.confirming)), count: 3))
        XCTAssertFalse(bus.sentAny(.share))
    }

    func testRoomcodeConfirmForADifferentRosterFailsTheRound() {
        let bus = StarBus.locked(nodes: 3)
        let otherHash = Digest.sha256(Data("a different roster".utf8))
        let data = bus.forged(by: 1, .roomcodeConfirm, content: Wire.roomcodeDigest(bus.engines[1].roster!), rosterHash: .some(otherHash))
        bus.deliver(2, .received(data, from: .host))
        XCTAssertEqual(bus.engines[2].phase, .failed(.rosterMismatch(PartyLabel(bus.engines[1].myLetter!.letter))))
    }

    // MARK: - Invariant 4: first-write-wins on canonical content

    func testIdenticalShareResentWithAFreshSignatureIsANoOp() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.submit([1: 5_000_000])
        let original = try XCTUnwrap(bus.originated(by: 1, .share).first)
        let resend = bus.forged(by: 1, .share, content: original.content)
        XCTAssertNotEqual(try Envelope.decodeAndVerify(resend), original, "ECDSA is randomized, bytes differ")
        bus.deliver(0, .received(resend, from: PeerID(1)))
        bus.run()
        XCTAssertEqual(bus.host.phase, .keyExchange)
        XCTAssertEqual(bus.sent.filter { $0.from == 0 && (try? Envelope.decodeAndVerify($0.data))?.action == .share }.count, 1,
                       "the duplicate is not forwarded again")
        bus.submit([0: 1_000_000, 2: 3_000_000])
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 3))
    }

    func testConflictingShareFailsTheRoundEverywhere() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.submit([1: 5_000_000])
        let letter = try XCTUnwrap(bus.engines[1].myLetter)
        let original = try XCTUnwrap(bus.originated(by: 1, .share).first)
        let conflicting = bus.forged(by: 1, .share, content: ShareString.format(try ShareString.parse(original.content) &+ 1))
        bus.deliver(0, .received(conflicting, from: PeerID(1)))
        bus.run()
        XCTAssertEqual(bus.host.phase, .failed(.conflictingMessage(letter)))
        XCTAssertEqual(bus.engines[2].phase, .failed(.aborted(.conflict)))
        XCTAssertNil(bus.host.maskKey)
    }

    func testBadSignatureThroughTheNormalRouteIsRejectedAndChangesNothing() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.intercept = { from, to, data in
            guard from == 0, to == 2, let message = try? Envelope.decodeAndVerify(data), message.action == .share else { return [data] }
            var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            object["content"] = "42"
            return [try! JSONSerialization.data(withJSONObject: object)]
        }
        bus.submit([0: 1, 1: 2, 2: 3])
        XCTAssertTrue(bus.rejections[2]?.contains(.message(.badSignature)) ?? false)
        XCTAssertNotEqual(bus.engines[2].phase, .complete(.agreed))
        bus.advance(ms: Deadlines.forTests.figureMs)
        XCTAssertEqual(bus.engines[2].phase, .failed(.timeout(.sharing)))
    }

    func testUnknownLetterOrMismatchedSenderIsRejected() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        // A roster member signing as another letter.
        let wrongLetter = bus.forged(by: 1, .share, content: "7", party: bus.engines[2].myLetter!.letter)
        bus.deliver(0, .received(wrongLetter, from: PeerID(1)))
        XCTAssertEqual(bus.rejections[0]?.last, .unknownSender)
        // A letter outside the roster.
        let outside = bus.forged(by: 1, .share, content: "7", party: "H")
        bus.deliver(0, .received(outside, from: PeerID(1)))
        XCTAssertEqual(bus.rejections[0]?.last, .unknownSender)
        // A roster member's message arriving on another member's connection.
        let wrongLink = bus.forged(by: 1, .share, content: "7")
        bus.deliver(0, .received(wrongLink, from: PeerID(2)))
        XCTAssertEqual(bus.rejections[0]?.last, .unknownSender)
        // A key outside the roster entirely.
        let stranger = Envelope.signed(action: .share, session: bus.host.session!, rosterHash: bus.host.roster!.rosterHash,
                                       party: "B", content: "7", key: SigningKey()).encoded()
        bus.deliver(2, .received(stranger, from: .host))
        XCTAssertEqual(bus.rejections[2]?.last, .unknownSender)
        XCTAssertEqual(bus.rejections[0], [.unknownSender, .unknownSender, .unknownSender], "each attempt rejected, none recorded")
        XCTAssertTrue(bus.host.sharesReceived.isEmpty)
        XCTAssertFalse(bus.sent.contains { $0.from == 0 && (try? Envelope.decodeAndVerify($0.data))?.action == .share },
                       "nothing was forwarded")
        XCTAssertEqual(bus.phases(), Array(repeating: .keyExchange, count: 3))
    }

    // MARK: - Invariant 5: one distinct share per round identity

    func testChangedFigureNeverProducesASecondShare() {
        let bus = StarBus.locked(nodes: 3)
        bus.submit([1: 10_000_000])
        bus.deliver(1, .submitFigure(20_000_000, generation: bus.engines[1].generation))
        XCTAssertEqual(bus.rejections[1], [.figureFrozen])
        bus.confirm()
        bus.deliver(1, .submitFigure(30_000_000, generation: bus.engines[1].generation))
        bus.submit([0: 0, 2: 0])
        XCTAssertEqual(bus.originated(by: 1, .share).count, 1)
        XCTAssertEqual(bus.host.sum, 10_000_000)
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 3))
    }

    func testDoubleTapsProduceOneLogicalOperation() {
        let bus = StarBus.locked(nodes: 3)
        for _ in 0..<3 { bus.confirm() }
        XCTAssertEqual(bus.originated(by: 1, .roomcodeConfirm).count, 1)
        XCTAssertEqual(bus.sent.filter { $0.from == 1 }.count, 2, "hello and one roomcode_confirm")
        for _ in 0..<3 { bus.submit([0: 1, 1: 2, 2: 3]) }
        for node in 0..<3 { XCTAssertEqual(bus.originated(by: node, .share).count, 1) }
        for node in 0..<3 { XCTAssertEqual(bus.originated(by: node, .resultConfirm).count, 1) }
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 3))
        XCTAssertEqual(bus.host.sum, 6)

        let fresh = StarBus.lobby(nodes: 3)
        fresh.deliver(0, .createRoom(label: "Again", maxSize: 3, nickname: "Host", entitled: false))
        XCTAssertEqual(fresh.rejections[0], [.wrongPhase])
        fresh.deliver(1, .joinRoom(nickname: "Again"))
        XCTAssertEqual(fresh.rejections[1], [.wrongPhase])
    }

    func testOutOfDomainFigureIsRefused() {
        let bus = StarBus.locked(nodes: 3)
        bus.deliver(1, .submitFigure(FixedPoint.cap, generation: bus.engines[1].generation))
        bus.deliver(2, .submitFigure(Int64.min, generation: bus.engines[2].generation))
        XCTAssertEqual(bus.rejections[1], [.outOfDomain])
        XCTAssertEqual(bus.rejections[2], [.outOfDomain])
        XCTAssertNil(bus.engines[1].frozenFigure)
    }

    // MARK: - Invariants 6 and 7: sum only when complete; signed agreement

    func testEquivocationShowsAsMismatchNeverAsAgreement() throws {
        let bus = StarBus.locked(nodes: 4)
        bus.confirm()
        // Node 3's share reaches node 2 as a different share, validly signed by node 3's key
        // (a participant equivocating with a relay that forwards selectively).
        let node3 = bus.engines[3].signingKey!.verifyingKey
        bus.intercept = { from, to, data in
            guard from == 0, to == 2, let message = try? Envelope.decodeAndVerify(data),
                  message.action == .share, message.sender == node3 else { return [data] }
            return [bus.forged(by: 3, .share, content: "12345")]
        }
        bus.submit([0: 1_000_000, 1: 2_000_000, 2: 3_000_000, 3: 4_000_000])
        let letter2 = try XCTUnwrap(bus.engines[2].myLetter)
        for node in [0, 1, 3] {
            XCTAssertEqual(bus.engines[node].phase, .complete(.mismatch([letter2])), "node \(node)")
        }
        let others = [0, 1, 3].map { bus.engines[$0].myLetter! }.sorted()
        XCTAssertEqual(bus.engines[2].phase, .complete(.mismatch(others)))
        XCTAssertFalse(bus.phases().contains(.complete(.agreed)))
    }

    func testMissingResultConfirmationsEndAsPartialNotAgreed() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.intercept = { from, _, data in
            (from == 1 && (try? Envelope.decodeAndVerify(data))?.action == .resultConfirm) ? [] : [data]
        }
        bus.submit([0: 1, 1: 2, 2: 3])
        let missing = try XCTUnwrap(bus.engines[1].myLetter)
        XCTAssertEqual(bus.host.phase, .collectingConfirmations)
        XCTAssertNotNil(bus.host.sum, "the sum is known, agreement is not")
        bus.advance(ms: Deadlines.forTests.confirmationsMs)
        XCTAssertEqual(bus.host.phase, .complete(.partial(missing: [missing])))
        XCTAssertEqual(bus.engines[2].phase, .complete(.partial(missing: [missing])))
        XCTAssertEqual(bus.engines[1].phase, .complete(.agreed), "node 1 received everyone else's")
    }

    func testLateConflictingResultConfirmMarksAnAgreedRoundDisputed() throws {
        let bus = StarBus.completed(figures: [1, 2, 3])
        let letter = try XCTUnwrap(bus.engines[1].myLetter)
        let late = bus.forged(by: 1, .resultConfirm, content: String(repeating: "0", count: 64))
        bus.deliver(2, .received(late, from: .host))
        XCTAssertEqual(bus.engines[2].phase, .complete(.disputed(letter)))
        XCTAssertEqual(bus.engines[2].sum, 6, "the record is kept, flagged")
        // An identical late resend changes nothing.
        let original = try XCTUnwrap(bus.originated(by: 1, .resultConfirm).first)
        bus.deliver(0, .received(bus.forged(by: 1, .resultConfirm, content: original.content), from: PeerID(1)))
        XCTAssertEqual(bus.host.phase, .complete(.agreed))
    }

    // MARK: - Invariant 8: deadlines

    func testSilentPeerTimesOutOnTheEngineClock() {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.submit([0: 1, 1: 2])
        XCTAssertEqual(bus.host.nextDeadline, bus.now + Deadlines.forTests.figureMs - 0)
        bus.advance(ms: Deadlines.forTests.figureMs - 1)
        XCTAssertEqual(bus.host.phase, .sharing)
        bus.advance(ms: 1)
        XCTAssertEqual(bus.host.phase, .failed(.timeout(.sharing)))
        XCTAssertEqual(bus.engines[1].phase, .failed(.timeout(.sharing)))
        XCTAssertEqual(bus.engines[2].phase, .failed(.timeout(.keyExchange)))
    }

    func testEveryWaitingStateHasADeadline() {
        let lobby = StarBus.lobby(nodes: 3)
        XCTAssertNotNil(lobby.host.nextDeadline)
        XCTAssertNotNil(lobby.engines[1].nextDeadline)
        lobby.advance(ms: Deadlines.forTests.lobbyMs)
        XCTAssertEqual(lobby.host.phase, .failed(.timeout(.lobby)))
        XCTAssertEqual(lobby.engines[1].phase, .failed(.timeout(.lobby)))

        let waitingForWelcome = StarBus(nodes: 3)
        waitingForWelcome.connected.insert(1)
        waitingForWelcome.deliver(1, .joinRoom(nickname: "Early"))
        XCTAssertNotNil(waitingForWelcome.engines[1].nextDeadline)

        let bus = StarBus.locked(nodes: 3)
        for engine in bus.engines { XCTAssertNotNil(engine.nextDeadline, "confirming") }
        bus.confirm()
        for engine in bus.engines { XCTAssertNotNil(engine.nextDeadline, "keyExchange") }
    }

    // MARK: - Invariant 9: restart

    func testRestartUsesFreshKeysNewSessionAndRejectsOldMessages() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        bus.submit([1: 5])
        let oldShare = try XCTUnwrap(bus.sent.first { $0.from == 1 && (try? Envelope.decodeAndVerify($0.data))?.action == .share }).data
        let oldSession = bus.host.session
        let oldKeys = bus.engines.map { $0.signingKey!.verifyingKey }
        bus.advance(ms: Deadlines.forTests.figureMs)
        XCTAssertEqual(bus.host.phase, .failed(.timeout(.keyExchange)), "the host never entered a figure")

        bus.deliver(0, .restart(generation: bus.host.generation))
        bus.run()
        XCTAssertEqual(bus.phases(), Array(repeating: .confirming, count: 3), "previous participants rejoin automatically")
        XCTAssertNotEqual(bus.host.session, oldSession)
        for (engine, old) in zip(bus.engines, oldKeys) {
            XCTAssertNotEqual(engine.signingKey!.verifyingKey, old)
            XCTAssertEqual(engine.session, bus.host.session)
            XCTAssertEqual(engine.generation, 2)
            XCTAssertFalse(engine.restartDroppedParticipants)
        }
        bus.deliver(0, .received(oldShare, from: PeerID(1)))
        XCTAssertEqual(bus.rejections[0]?.last, .wrongSession)

        bus.confirm()
        bus.submit([0: 7, 1: 8, 2: 9])
        XCTAssertEqual(bus.phases(), Array(repeating: .complete(.agreed), count: 3))
        XCTAssertEqual(bus.host.sum, 24)
    }

    func testRestartAfterSomeoneLeftWarnsAboutDifferencing() throws {
        let bus = StarBus.locked(nodes: 4)
        bus.confirm()
        let leaving = bus.engines[3].myLetter
        bus.drop(3)
        bus.run()
        XCTAssertEqual(bus.host.phase, .failed(.peerLeft(leaving)), "host names who left")
        bus.deliver(0, .restart(generation: bus.host.generation))
        bus.run()
        for node in 0..<3 {
            XCTAssertEqual(bus.engines[node].phase, .confirming)
            XCTAssertEqual(bus.engines[node].roster?.size, 3)
            XCTAssertTrue(bus.engines[node].restartDroppedParticipants, "SPEC invariant 13, node \(node)")
        }
    }

    func testStaleGenerationActionsAreDropped() {
        let bus = StarBus.locked(nodes: 3)
        let oldGeneration = bus.engines[1].generation
        bus.advance(ms: Deadlines.forTests.confirmingMs)
        bus.deliver(0, .restart(generation: bus.host.generation))
        bus.run()
        bus.deliver(1, .submitFigure(5, generation: oldGeneration))
        bus.deliver(1, .confirmRoomCode(generation: oldGeneration))
        XCTAssertEqual(bus.rejections[1], [.staleGeneration, .staleGeneration])
        XCTAssertNil(bus.engines[1].frozenFigure)
        bus.deliver(0, .restart(generation: oldGeneration))
        XCTAssertEqual(bus.rejections[0]?.last, .staleGeneration)
        XCTAssertEqual(bus.host.generation, 2, "a double-tapped restart restarts once")
    }

    func testOnlyTheHostCanRestart() {
        let bus = StarBus.locked(nodes: 3)
        bus.advance(ms: Deadlines.forTests.confirmingMs)
        bus.deliver(1, .restart(generation: bus.engines[1].generation))
        XCTAssertEqual(bus.rejections[1], [.wrongPhase])
    }

    // MARK: - Transport failure mid-state (retro gate)

    func testTransportErrorMidRoundCleansUpEverywhere() {
        let bus = StarBus.locked(nodes: 4)
        bus.confirm()
        bus.submit([0: 1, 1: 2])
        let leftLetter = bus.engines[2].myLetter
        bus.drop(2)
        bus.run()
        XCTAssertEqual(bus.host.phase, .failed(.peerLeft(leftLetter)))
        XCTAssertEqual(bus.engines[1].phase, .failed(.aborted(.peerLeft)))
        XCTAssertEqual(bus.engines[3].phase, .failed(.aborted(.peerLeft)))
        XCTAssertEqual(bus.engines[2].phase, .failed(.connectionLost))
        for engine in bus.engines {
            XCTAssertNil(engine.maskKey)
            XCTAssertNil(engine.frozenFigure)
            XCTAssertNil(engine.nextDeadline)
        }
        // Late traffic after the failure changes nothing and sends nothing.
        let before = bus.sent.count
        bus.submit([3: 4])
        bus.deliver(1, .received(bus.forged(by: 3, .share, content: "4"), from: .host))
        XCTAssertEqual(bus.sent.count, before)
        XCTAssertEqual(bus.engines[1].phase, .failed(.aborted(.peerLeft)))
    }

    func testJoinerLosingTheHostFailsAndLateConnectionsAreRefused() {
        let bus = StarBus.locked(nodes: 3)
        bus.connected.insert(5)
        let effects = bus.deliver(0, .peerConnected(PeerID(5)))
        XCTAssertEqual(effects, [.disconnect(PeerID(5))])
        bus.deliver(1, .peerDisconnected(.host))
        XCTAssertEqual(bus.engines[1].phase, .failed(.connectionLost))
    }

    // MARK: - Invariant 11: entitlement inside the state machine

    func testEntitlementIsEnforcedAtCreationAndAdmission() {
        let unpaid = StarBus(nodes: 4)
        unpaid.deliver(0, .createRoom(label: "Bonus", maxSize: 4, nickname: "Host", entitled: false))
        XCTAssertEqual(unpaid.host.phase, .idle)
        XCTAssertEqual(unpaid.rejections[0], [.notEntitled])

        // Without entitlement the room is capped at three, and admission enforces it.
        let bus = StarBus(nodes: 4)
        bus.deliver(0, .createRoom(label: "Bonus", maxSize: 3, nickname: "Host", entitled: false))
        for k in 1...3 { bus.join(k) }
        XCTAssertEqual(bus.host.pendingJoiners.count, 3)
        bus.admitAll()
        XCTAssertEqual(bus.host.admittedCount, 2)
        XCTAssertEqual(bus.rejections[0], [.roomFull])
        bus.start()
        XCTAssertEqual(bus.host.roster?.size, 3)
    }

    func testSizeBoundsAndStartNeedsThreePeople() {
        let tooBig = StarBus(nodes: 1)
        tooBig.deliver(0, .createRoom(label: "L", maxSize: 9, nickname: "Host", entitled: true))
        tooBig.deliver(0, .createRoom(label: "L", maxSize: 2, nickname: "Host", entitled: true))
        tooBig.deliver(0, .createRoom(label: "", maxSize: 3, nickname: "Host", entitled: true))
        XCTAssertEqual(tooBig.rejections[0], [.invalidInput, .invalidInput, .invalidInput])

        let bus = StarBus(nodes: 2)
        bus.deliver(0, .createRoom(label: "L", maxSize: 3, nickname: "Host", entitled: false))
        bus.join(1)
        bus.admitAll()
        bus.start()
        XCTAssertEqual(bus.host.phase, .lobby)
        XCTAssertEqual(bus.rejections[0]?.last, .notEnoughPeople)
    }

    // MARK: - Message domain in the engine: floods, queues, versions, decline

    func testPendingQueueAndMessageFloodsAreBounded() throws {
        let bus = StarBus.lobby(nodes: 3)
        for k in 10..<(10 + RoundEngine.maxConnections) {
            bus.connected.insert(k)
            bus.deliver(0, .peerConnected(PeerID(k)))
        }
        XCTAssertEqual(bus.connected.count, RoundEngine.maxConnections, "extra connections are refused")

        let locked = StarBus.locked(nodes: 3)
        locked.confirm()
        let spam = locked.forged(by: 1, .roomcodeConfirm, content: Wire.roomcodeDigest(locked.engines[1].roster!))
        for _ in 0..<(RoundEngine.maxMessagesPerPeer + 5) where locked.connected.contains(1) {
            locked.deliver(0, .received(spam, from: PeerID(1)))
        }
        XCTAssertFalse(locked.connected.contains(1), "a flooding peer is disconnected")
        XCTAssertTrue(locked.rejections[0]?.contains(.flood) ?? false)
    }

    func testUnsupportedVersionIsSurfaced() {
        let bus = StarBus.lobby(nodes: 3)
        bus.deliver(1, .received(Data("{\"v\":2}".utf8), from: .host))
        XCTAssertEqual(bus.rejections[1], [.message(.unsupportedVersion(2))])
        XCTAssertEqual(bus.engines[1].lastIncompatibleVersion, 2)
    }

    func testDeclinedJoinerIsToldAndDisconnected() throws {
        let bus = StarBus.lobby(nodes: 3)
        let pending = try XCTUnwrap(bus.host.pendingJoiners.first)
        let node = try XCTUnwrap(bus.joinerNodes.first { bus.engines[$0].signingKey?.verifyingKey == pending.verifyingKey })
        bus.deliver(0, .decline(pending.verifyingKey, generation: bus.host.generation))
        bus.run()
        XCTAssertEqual(bus.engines[node].phase, .failed(.declined))
        XCTAssertFalse(bus.connected.contains(node))
        XCTAssertEqual(bus.host.pendingJoiners.count, 1)
    }
}

extension StarBus {
    /// The hello content joiner `node` sent.
    func hello(of node: Int) -> String {
        sent.first { $0.from == node }.flatMap { try? Envelope.decodeAndVerify($0.data) }?.content ?? ""
    }
}
