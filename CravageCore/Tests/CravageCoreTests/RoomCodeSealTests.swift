import XCTest
import Foundation
@testable import CravageCore

/// The sealed room code (council 2026-10-03, docs/review/council/2026-10-03-room-code-commit-reveal.md;
/// SPEC section 3 invariant 14). Every party seals a fresh random value in its signed hello, reveals
/// it only once it holds the locked roster (and so every seal), and the code covers every revealed
/// value. A host that controls both rooms of a split can then no longer search for two rosters with
/// one code: each phone's code depends on a value nobody knew when the roster was fixed.
final class RoomCodeSealTests: XCTestCase {

    private func isAction(_ data: Data, _ action: MessageAction) -> Bool {
        (try? Envelope.decodeAndVerify(data))?.action == action
    }

    // MARK: - Ordering

    func testNoValueIsRevealedBeforeTheRosterIsLocked() {
        let bus = StarBus.lobby(nodes: 4)
        bus.admitAll()
        XCTAssertFalse(bus.sentAny(.roomcodeReveal), "a reveal before lock lets the host choose its seals after seeing it")
        bus.start()
        for node in 0..<4 {
            XCTAssertEqual(bus.originated(by: node, .roomcodeReveal).count, 1, "node \(node) reveals exactly once")
        }
    }

    func testCodeAppearsOnlyAfterEveryRevealHasOpenedItsSeal() {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        bus.intercept = { [unowned self] from, _, data in
            from == 2 && self.isAction(data, .roomcodeReveal) ? [] : [data]
        }
        bus.start()
        // Phone 2 holds every value; the host and phone 1 are still missing phone 2's.
        for node in 0...1 {
            XCTAssertEqual(bus.engines[node].phase, .revealing)
            XCTAssertNil(bus.engines[node].roomCode, "no code until every value is in")
        }
        bus.deliver(1, .confirmRoomCode(generation: bus.engines[1].generation))
        XCTAssertEqual(bus.rejections[1], [.wrongPhase], "nobody can confirm a code that does not exist yet")
        XCTAssertTrue(bus.originated(by: 1, .roomcodeConfirm).isEmpty)
    }

    func testAWithheldRevealTimesOutVisibly() {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        bus.intercept = { [unowned self] from, _, data in
            from == 0 && self.isAction(data, .roomcodeReveal) ? [] : [data]
        }
        bus.start()
        bus.advance(ms: Deadlines.forTests.revealMs)
        for node in 1..<3 {
            XCTAssertEqual(bus.engines[node].phase, .failed(.timeout(.revealing)), "no silent retry")
        }
    }

    func testEveryPhoneShowsTheSameCodeOnceAllRevealsAreIn() throws {
        let bus = StarBus.locked(nodes: 5)
        let code = try XCTUnwrap(bus.host.roomCode)
        for engine in bus.engines {
            XCTAssertEqual(engine.phase, .confirming)
            XCTAssertEqual(engine.roomCode, code)
        }
    }

    // MARK: - Opening and first write wins

    func testARevealThatDoesNotOpenItsSealFailsTheRound() throws {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        bus.intercept = { [unowned self] from, _, data in
            guard from == 2, self.isAction(data, .roomcodeReveal) else { return [data] }
            return [bus.forged(by: 2, .roomcodeReveal, content: Hex.encode(Data(repeating: 7, count: 32)))]
        }
        bus.start()
        let letter = try XCTUnwrap(bus.engines[2].myLetter)
        XCTAssertEqual(bus.host.phase, .failed(.revealMismatch(letter)))
        XCTAssertEqual(bus.engines[1].phase, .failed(.aborted(.rosterMismatch)), "the others hear the phones disagreed")
        XCTAssertNil(bus.host.roomCode)
        XCTAssertFalse(bus.sentAny(.roomcodeConfirm))
    }

    func testASecondDifferentRevealFailsTheRoundAndARepeatIsANoOp() throws {
        let bus = StarBus.locked(nodes: 3)
        let original = try XCTUnwrap(bus.originated(by: 2, .roomcodeReveal).first)
        let repeated = bus.forged(by: 2, .roomcodeReveal, content: original.content)
        bus.deliver(0, .received(repeated, from: PeerID(2)))
        XCTAssertEqual(bus.host.phase, .confirming, "an identical repeat changes nothing")
        let other = bus.forged(by: 2, .roomcodeReveal, content: Hex.encode(Data(repeating: 9, count: 32)))
        bus.deliver(0, .received(other, from: PeerID(2)))
        XCTAssertEqual(bus.host.phase, .failed(.conflictingMessage(try XCTUnwrap(bus.engines[2].myLetter))))
    }

    func testMalformedRevealIsRejected() {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        bus.intercept = { [unowned self] from, _, data in
            guard from == 2, self.isAction(data, .roomcodeReveal) else { return [data] }
            return [bus.forged(by: 2, .roomcodeReveal, content: "ABCD"), data]
        }
        bus.start()
        XCTAssertTrue(bus.rejections[0]?.contains(.invalidContent) ?? false)
        XCTAssertEqual(bus.host.phase, .confirming)
    }

    // MARK: - What the seal and the code cover

    func testSealBindsSessionKeyAndLabel() {
        let session = SessionID.random()
        let key = SigningKey().verifyingKey
        let value = RoomCodeSeal.randomValue()
        let seal = RoomCodeSeal.commitment(session: session, verifyingKey: key, label: "Salary", value: value)
        XCTAssertEqual(seal.count, 32, "the full digest, never truncated")
        XCTAssertNotEqual(seal, RoomCodeSeal.commitment(session: SessionID.random(), verifyingKey: key, label: "Salary", value: value))
        XCTAssertNotEqual(seal, RoomCodeSeal.commitment(session: session, verifyingKey: SigningKey().verifyingKey, label: "Salary", value: value),
                          "a copied seal cannot be opened under another key")
        XCTAssertNotEqual(seal, RoomCodeSeal.commitment(session: session, verifyingKey: key, label: "Bonus", value: value))
        XCTAssertNotEqual(value, RoomCodeSeal.randomValue())
        XCTAssertEqual(value.count, 32)
    }

    func testCodeCoversEveryRevealedValue() throws {
        let bus = StarBus.locked(nodes: 4)
        let roster = try XCTUnwrap(bus.host.roster)
        let values = (0..<4).map { Data(repeating: UInt8($0 + 1), count: 32) }
        let base = RoomFingerprint(roster: roster, revealsInLetterOrder: values)
        for index in values.indices {
            var changed = values
            changed[index] = Data(repeating: 0xEE, count: 32)
            XCTAssertNotEqual(RoomFingerprint(roster: roster, revealsInLetterOrder: changed), base, "reveal \(index)")
        }
    }

    func testRosterHashCoversEverySeal() throws {
        let session = SessionID.random()
        func entry(_ seal: UInt8) -> RosterEntry {
            RosterEntry(verifyingKey: SigningKey().verifyingKey, maskPublicKey: MaskPrivateKey().publicKey,
                        commitment: Data(repeating: seal, count: 32), nickname: "n")
        }
        let entries = [entry(1), entry(2), entry(3)]
        let base = try Roster(session: session, label: "l", entries: entries)
        let changed = try Roster(session: session, label: "l", entries: [entries[0], entries[1],
            RosterEntry(verifyingKey: entries[2].verifyingKey, maskPublicKey: entries[2].maskPublicKey,
                        commitment: Data(repeating: 4, count: 32), nickname: "n")])
        XCTAssertNotEqual(base.rosterHash, changed.rosterHash)
        XCTAssertThrowsError(try Roster(session: session, label: "l", entries: [entries[0], entries[1],
            RosterEntry(verifyingKey: entries[2].verifyingKey, maskPublicKey: entries[2].maskPublicKey,
                        commitment: Data(repeating: 4, count: 31), nickname: "n")])) {
            XCTAssertEqual($0 as? RosterError, .invalidCommitment)
        }
    }

    // MARK: - One roster, one seal, per session

    func testAJoinerAcceptsExactlyOneRosterPerSession() throws {
        let bus = StarBus.locked(nodes: 3)
        let joiner = bus.engines[1]
        let code = try XCTUnwrap(joiner.roomCode)
        let rosterHash = try XCTUnwrap(joiner.roster?.rosterHash)
        // A different second roster, signed by the real host for the same session, with joiner 2
        // swapped for a participant the host invented: after the first roster's values are revealed,
        // accepting it would let the host search for a matching code again.
        let ghost = SigningKey(), ghostMask = MaskPrivateKey()
        let ghostSeal = RoomCodeSeal.commitment(session: bus.host.session!, verifyingKey: ghost.verifyingKey,
                                                label: "Average salary", value: RoomCodeSeal.randomValue())
        let ghostHello = Wire.Hello(mask: ghostMask.publicKey, nonce: bus.host.nonce!, commitment: ghostSeal, nickname: "Joiner 2")
        let ghostSig = ghost.sign(CanonicalMessage(action: .pubkey, session: bus.host.session!.hex,
                                                   party: ghost.verifyingKey.base64, content: ghostHello.content).string)
        let replaced = bus.engines[2].signingKey!.verifyingKey.base64
        let entries = bus.host.signedHellosForTesting().map { entry in
            entry.vk == replaced ? Wire.SignedHello(vk: ghost.verifyingKey.base64, mask: ghostMask.publicKey.base64,
                                                    commit: Hex.encode(ghostSeal), nick: "Joiner 2", sig: ghostSig.base64) : entry
        }
        let second = Envelope.signed(action: .control, session: bus.host.session!, party: Wire.hostParty,
                                     content: Wire.encode(.roster(entries)), key: bus.host.signingKey!).encoded()
        bus.deliver(1, .received(second, from: .host))
        XCTAssertEqual(bus.rejections[1], [.wrongPhase])
        XCTAssertEqual(joiner.roomCode, code)
        XCTAssertEqual(joiner.roster?.rosterHash, rosterHash)
    }

    func testEverySessionAndRestartSealsAFreshValue() throws {
        let bus = StarBus.locked(nodes: 3)
        let firstValue = try XCTUnwrap(bus.engines[1].sealValue)
        bus.deliver(0, .restart(generation: bus.host.generation))
        bus.run()
        for node in 1..<3 { bus.deliver(node, .acceptRestart(generation: bus.engines[node].generation)) }
        bus.run()
        XCTAssertEqual(bus.host.phase, .confirming)
        XCTAssertNotEqual(bus.engines[1].sealValue, firstValue, "a new session alone would change the seal; the value must change too")
    }

    func testJoinerRejectsARosterThatAltersItsOwnSeal() throws {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        bus.intercept = { from, to, data in
            guard from == 0, to == 1, let message = try? Envelope.decodeAndVerify(data), message.action == .control,
                  case let .roster(entries)? = Wire.decodeControl(message.content) else { return [data] }
            let mine = bus.engines[1].signingKey!.verifyingKey.base64
            let altered = entries.map { entry in
                entry.vk == mine ? Wire.SignedHello(vk: entry.vk, mask: entry.mask, commit: String(repeating: "0", count: 64),
                                                    nick: entry.nick, sig: entry.sig) : entry
            }
            return [Envelope.signed(action: .control, session: bus.host.session!, party: Wire.hostParty,
                                    content: Wire.encode(.roster(altered)), key: bus.host.signingKey!).encoded()]
        }
        bus.start()
        XCTAssertEqual(bus.engines[1].phase, .failed(.invalidRoster))
        XCTAssertTrue(bus.originated(by: 1, .roomcodeReveal).isEmpty, "no reveal under a roster it did not seal")
    }

    // MARK: - "The codes don't match"

    /// Decision 2026-10-03: a person who sees a different code ends the round with a reason,
    /// not a silent leave. Nothing of a figure has left any phone at that point.
    func testCodesDontMatchEndsTheRoundWithAReason() throws {
        let joinerSaw = StarBus.locked(nodes: 3)
        let letter = try XCTUnwrap(joinerSaw.engines[1].myLetter)
        joinerSaw.deliver(1, .codesDiffer(generation: joinerSaw.engines[1].generation))
        joinerSaw.run()
        XCTAssertEqual(joinerSaw.engines[1].phase, .failed(.codesDiffered))
        XCTAssertEqual(joinerSaw.host.phase, .failed(.codeDisputed(letter)))
        XCTAssertEqual(joinerSaw.engines[2].phase, .failed(.codeDisputed(letter)),
                       "the others learn whose phone showed a different code, not just that a phone left")
        XCTAssertFalse(joinerSaw.sentAny(.share))

        let hostSaw = StarBus.locked(nodes: 3)
        let hostLetter = try XCTUnwrap(hostSaw.host.myLetter)
        hostSaw.deliver(0, .codesDiffer(generation: hostSaw.host.generation))
        hostSaw.run()
        XCTAssertEqual(hostSaw.host.phase, .failed(.codesDiffered))
        for node in 1..<3 { XCTAssertEqual(hostSaw.engines[node].phase, .failed(.codeDisputed(hostLetter))) }

        let noCodeYet = StarBus.lobby(nodes: 3)
        noCodeYet.admitAll()
        noCodeYet.intercept = { _, _, data in (try? Envelope.decodeAndVerify(data))?.action == .roomcodeReveal ? [] : [data] }
        noCodeYet.start()
        noCodeYet.deliver(1, .codesDiffer(generation: noCodeYet.engines[1].generation))
        XCTAssertEqual(noCodeYet.rejections[1], [.wrongPhase], "there is no code to disagree about yet")
        XCTAssertEqual(noCodeYet.engines[1].phase, .revealing)
    }

    /// A dispute is a signed, roster-bound message like any other: content that is not this
    /// roster's roomcode digest is refused and the round goes on.
    func testADisputeMustCarryTheRoomcodeDigest() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.deliver(0, .received(bus.forged(by: 2, .roomcodeDispute, content: String(repeating: "0", count: 64)), from: PeerID(2)))
        XCTAssertEqual(bus.rejections[0], [.invalidContent])
        XCTAssertEqual(bus.host.phase, .confirming)
        bus.confirm()
        bus.submit([0: 1, 1: 2, 2: 3])
        XCTAssertEqual(bus.host.phase, .complete(.agreed), "a refused dispute does not stop an honest round")

        let late = StarBus.completed(figures: [1, 2, 3])
        let digest = Wire.roomcodeDigest(try XCTUnwrap(late.host.roster))
        late.deliver(0, .received(late.forged(by: 2, .roomcodeDispute, content: digest), from: PeerID(2)))
        XCTAssertEqual(late.host.phase, .complete(.agreed), "after the result, a dispute changes nothing")
    }

    /// Review 2026-10-04, findings 1 to 3: an honest dispute can only reach a phone that is
    /// confirming, entering its figure or sharing, because nobody can dispute before the code
    /// exists and nobody reaches the result barrier while the disputer has sent no share. Anywhere
    /// else it would blame a named phone for a code nobody saw, so it is refused and nothing ends.
    /// A key outside the roster ends nothing either.
    func testADisputeIsRefusedWhereNoHonestPhoneCouldHaveSentIt() throws {
        let revealing = StarBus.lobby(nodes: 3)
        revealing.admitAll()
        revealing.intercept = { _, _, data in (try? Envelope.decodeAndVerify(data))?.action == .roomcodeReveal ? [] : [data] }
        revealing.start()
        XCTAssertEqual(revealing.host.phase, .revealing)
        let digest = Wire.roomcodeDigest(try XCTUnwrap(revealing.host.roster))
        revealing.deliver(0, .received(revealing.forged(by: 2, .roomcodeDispute, content: digest), from: PeerID(2)))
        XCTAssertEqual(revealing.rejections[0], [.wrongPhase], "no code exists yet, so nobody saw a different one")
        XCTAssertEqual(revealing.host.phase, .revealing)

        let finishing = StarBus.locked(nodes: 3)
        finishing.confirm()
        finishing.intercept = { _, _, data in (try? Envelope.decodeAndVerify(data))?.action == .resultConfirm ? [] : [data] }
        finishing.submit([0: 1, 1: 2, 2: 3])
        XCTAssertEqual(finishing.host.phase, .collectingConfirmations)
        let late = Wire.roomcodeDigest(try XCTUnwrap(finishing.host.roster))
        finishing.deliver(0, .received(finishing.forged(by: 2, .roomcodeDispute, content: late), from: PeerID(2)))
        XCTAssertEqual(finishing.rejections[0], [.wrongPhase], "every share is in; this phone confirmed the code")
        XCTAssertEqual(finishing.host.phase, .collectingConfirmations)

        let outsider = StarBus.locked(nodes: 3)
        let roster = try XCTUnwrap(outsider.host.roster)
        let stranger = SigningKey()
        let forged = Envelope.signed(action: .roomcodeDispute, session: outsider.host.session!, rosterHash: roster.rosterHash,
                                     party: "B", content: Wire.roomcodeDigest(roster), key: stranger).encoded()
        outsider.deliver(0, .received(forged, from: PeerID(2)))
        outsider.deliver(2, .received(forged, from: .host))
        XCTAssertEqual(outsider.rejections[0], [.unknownSender])
        XCTAssertEqual(outsider.rejections[2], [.unknownSender])
        XCTAssertEqual(outsider.host.phase, .confirming)
        XCTAssertEqual(outsider.engines[2].phase, .confirming)
    }

    /// Review 2026-10-04, finding 4: the disputer stays connected, so a restart offers it a
    /// place like everyone else; the offer asks first and the new round makes a new code.
    func testAfterADisputeTheHostCanRestartWithEveryone() throws {
        let bus = StarBus.locked(nodes: 3)
        bus.deliver(1, .codesDiffer(generation: bus.engines[1].generation))
        bus.run()
        bus.deliver(0, .restart(generation: bus.host.generation))
        bus.run()
        XCTAssertNotNil(bus.engines[1].restartOffer, "the person who disputed is asked, not dropped")
        XCTAssertNotNil(bus.engines[2].restartOffer)
    }

    /// Review 2026-10-03, finding 3: a person who confirmed and then sees a different code can
    /// still stop the round after the last confirmation arrives, until a figure is entered.
    func testCodesDontMatchStillWorksUntilAFigureIsEntered() {
        let bus = StarBus.locked(nodes: 3)
        bus.confirm()
        XCTAssertEqual(bus.engines[1].phase, .keyExchange)
        bus.deliver(1, .codesDiffer(generation: bus.engines[1].generation))
        XCTAssertEqual(bus.engines[1].phase, .failed(.codesDiffered))

        let sent = StarBus.locked(nodes: 3)
        sent.confirm()
        sent.submit([1: 5])
        XCTAssertEqual(sent.engines[1].phase, .sharing)
        sent.deliver(1, .codesDiffer(generation: sent.engines[1].generation))
        XCTAssertEqual(sent.rejections[1], [.wrongPhase], "after a share has gone, stopping is Leave, not a code dispute")
    }

    // MARK: - Wire edges (review 2026-10-03, finding 7)

    func testHelloNicknameMayContainABarAfterTheSeal() throws {
        let seal = RoomCodeSeal.randomValue()
        let hello = Wire.Hello(mask: MaskPrivateKey().publicKey, nonce: Wire.randomNonce(), commitment: seal, nickname: "Pat|Q")
        let parsed = try XCTUnwrap(Wire.Hello.parse(hello.content))
        XCTAssertEqual(parsed, hello)
        XCTAssertNil(Wire.Hello.parse(hello.content.replacingOccurrences(of: Hex.encode(seal), with: Hex.encode(seal).uppercased())),
                     "the seal is canonical lowercase hex")
    }

    func testARevealBoundToAnotherRosterFailsTheRound() throws {
        let bus = StarBus.lobby(nodes: 3)
        bus.admitAll()
        bus.intercept = { from, _, data in
            guard from == 2, let message = try? Envelope.decodeAndVerify(data), message.action == .roomcodeReveal else { return [data] }
            return [bus.forged(by: 2, .roomcodeReveal, content: message.content, rosterHash: Data(repeating: 1, count: 32))]
        }
        bus.start()
        XCTAssertEqual(bus.host.phase, .failed(.rosterMismatch(try XCTUnwrap(bus.engines[2].myLetter))))
        XCTAssertNil(bus.host.roomCode)
    }

    // MARK: - The attack itself, at a width small enough to run (council condition 4)

    /// At 16 bits instead of 40, a host that controls two rooms searches its own inputs for two
    /// different rosters with one code. If it knew every value in advance (as it knew every input to
    /// the old code), the search succeeds in about 2^8 tries a room. With the seal, the honest
    /// values arrive only after both rosters are locked, so the pairs it found match no more often
    /// than chance (2^-16 each).
    func testNarrowedCodeShowsTheSplitSearchAndThatTheSealDefeatsIt() throws {
        let width = 2
        struct Member { let key: VerifyingKey; let mask: MaskPublicKey; let seal: Data }
        func member() -> Member {
            Member(key: SigningKey().verifyingKey, mask: MaskPrivateKey().publicKey, seal: RoomCodeSeal.randomValue())
        }
        let host1 = member(), pat = member(), ghost1 = member()
        let host2 = member(), victim = member(), ghost2 = member()
        let session1 = SessionID.random(), session2 = SessionID.random()
        func roster(_ session: SessionID, _ members: [(Member, String)]) throws -> Roster {
            try Roster(session: session, label: "Annual bonus", entries: members.map {
                RosterEntry(verifyingKey: $0.0.key, maskPublicKey: $0.0.mask, commitment: $0.0.seal, nickname: $0.1)
            })
        }
        func narrow(_ roster: Roster, _ values: [VerifyingKey: Data]) -> Data {
            RoomFingerprint.digest(roster: roster, revealsInLetterOrder: roster.parties.map { values[$0.verifyingKey]! }).prefix(width)
        }
        // The host's own and invented participants' values are its to choose; it guesses the honest ones.
        var guessed: [VerifyingKey: Data] = [:]
        for m in [host1, pat, ghost1, host2, victim, ghost2] { guessed[m.key] = Data(repeating: 0, count: 32) }

        var table: [Data: Roster] = [:]
        for i in 0..<1024 {
            let r = try roster(session1, [(host1, "Host"), (pat, "Pat"), (ghost1, "Vic \(i)")])
            table[narrow(r, guessed)] = r
        }
        var pairs: [(Roster, Roster)] = []
        for j in 0..<8192 where pairs.count < 32 {
            let r = try roster(session2, [(host2, "Host"), (victim, "Vic"), (ghost2, "Pat \(j)")])
            if let match = table[narrow(r, guessed)] { pairs.append((match, r)) }
        }
        XCTAssertGreaterThanOrEqual(pairs.count, 8, "with every value known, the split search succeeds quickly")

        // Sealed: the rosters are locked, and only then do Pat and Vic reveal values nobody knew.
        var revealed = guessed
        revealed[pat.key] = RoomCodeSeal.randomValue()
        revealed[victim.key] = RoomCodeSeal.randomValue()
        let stillMatching = pairs.filter { narrow($0.0, revealed) == narrow($0.1, revealed) }.count
        XCTAssertLessThanOrEqual(stillMatching, 2, "found pairs match only by chance (expected \(pairs.count) x 2^-16)")
    }
}
