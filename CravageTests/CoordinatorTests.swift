import XCTest
@testable import CravageCore
@testable import Cravage

// MARK: - Fakes

@MainActor
final class FakeClock: RoundClock {
    var now: UInt64 = 1_000
    private var sleepers: [(due: UInt64, continuation: CheckedContinuation<Void, Error>)] = []

    func nowMs() -> UInt64 { now }

    func sleep(untilMs: UInt64) async throws {
        if untilMs <= now { return }
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append((untilMs, continuation))
        }
        try Task.checkCancellation()
    }

    /// Moves time forward and wakes every sleeper that is now due.
    func advance(ms: UInt64) async {
        now += ms
        let due = sleepers.filter { $0.due <= now }
        sleepers.removeAll { $0.due <= now }
        for sleeper in due { sleeper.continuation.resume() }
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
final class FakeEntitlement: EntitlementProvider {
    var unlocked: Bool
    var asked = 0
    var gate: CheckedContinuation<Void, Never>?
    var holdAnswer = false
    init(unlocked: Bool) { self.unlocked = unlocked }
    func hasVerifiedUnlock() async -> Bool {
        asked += 1
        if holdAnswer { await withCheckedContinuation { gate = $0 } }
        return unlocked
    }
}

/// An in-memory star: phone 0 hosts, the others join. Deliveries are queued and flushed so no
/// coordinator is re-entered while it is still carrying out effects.
@MainActor
final class FakeStar {
    final class Transport: RoundTransport {
        var onEvent: ((TransportEvent) -> Void)?
        weak var star: FakeStar?
        let index: Int
        var hosting: (label: String, size: Int)?
        var advertising = false
        var browsing = false
        var sentCount = 0
        var connectionAttempts = 0
        var sendFailures = 0
        init(index: Int) { self.index = index }
        func startHosting(label: String, size: Int, hostNickname: String) { hosting = (label, size); advertising = true }
        func stopAdvertising() { advertising = false }
        func startBrowsing() {
            browsing = true
            if let advert = star?.advert { onEvent?(.roomsChanged([advert])) }
        }
        func stopBrowsing() { browsing = false }
        func connect(to roomID: String) {
            connectionAttempts += 1
            star?.connect(joiner: index)
        }
        func send(_ data: Data, to peer: PeerID) { sentCount += 1; star?.enqueue(from: index, to: peer, data) }
        func disconnect(_ peer: PeerID) { star?.drop(index == 0 ? peer.raw : index) }
        func stopAll() { hosting = nil; advertising = false; browsing = false }
    }

    let transports: [Transport]
    let clock = FakeClock()
    var coordinators: [RoundCoordinator] = []
    var connected: Set<Int> = []
    private var queue: [(to: Int, event: TransportEvent)] = []

    var advert: RoomAdvert? {
        guard let hosting = transports[0].hosting, transports[0].advertising else { return nil }
        return RoomAdvert(id: "room", label: hosting.label, size: hosting.size, hostNickname: "Host", protocolVersion: CravageCore.protocolVersion)
    }

    init(phones: Int, entitlement: FakeEntitlement) {
        transports = (0..<phones).map { Transport(index: $0) }
        for transport in transports {
            transport.star = self
            coordinators.append(RoundCoordinator(transport: transport, clock: clock, entitlement: entitlement,
                                                 deadlines: Deadlines(lobbyMs: 600_000, confirmingMs: 60_000, figureMs: 90_000,
                                                                      confirmationsMs: 10_000, helloMs: 5_000)))
        }
    }

    func connect(joiner: Int) {
        connected.insert(joiner)
        queue.append((0, .peerConnected(PeerID(joiner))))
    }

    func enqueue(from: Int, to peer: PeerID, _ data: Data) {
        let target = from == 0 ? peer.raw : 0
        let link = from == 0 ? target : from
        guard connected.contains(link) else { return }
        queue.append((target, .received(data, from: from == 0 ? .host : PeerID(from))))
    }

    func drop(_ joiner: Int) {
        guard connected.remove(joiner) != nil else { return }
        queue.removeAll { $0.to == joiner }
        queue.append((0, .peerDisconnected(PeerID(joiner))))
        queue.append((joiner, .peerDisconnected(.host)))
    }

    func flush() {
        var steps = 0
        while !queue.isEmpty {
            steps += 1
            precondition(steps < 10_000, "star did not go quiet")
            let item = queue.removeFirst()
            if case let .received(_, from) = item.event {
                let link = item.to == 0 ? from.raw : item.to
                guard connected.contains(link) else { continue }
            }
            transports[item.to].onEvent?(item.event)
        }
    }
}

// MARK: - Tests

@MainActor
final class CoordinatorTests: XCTestCase {

    /// SPEC invariant 11 through the coordinator: an unpaid host cannot open a room for four,
    /// and the room is never advertised.
    func testEntitlementIsEnforcedAtRoomCreationThroughTheCoordinator() async {
        let entitlement = FakeEntitlement(unlocked: false)
        let star = FakeStar(phones: 1, entitlement: entitlement)
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 4, nickname: "Sam")
        XCTAssertEqual(entitlement.asked, 1)
        XCTAssertEqual(host.engine.phase, .idle)
        XCTAssertEqual(host.lastRejection, .notEntitled)
        XCTAssertNil(star.transports[0].hosting, "a refused room is never advertised")

        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertEqual(entitlement.asked, 1, "three people never needs the store")
        XCTAssertEqual(host.engine.phase, .lobby)
        XCTAssertEqual(star.transports[0].hosting?.size, 3)
    }

    /// A room advertising another protocol version is refused before any connection is opened.
    func testJoiningARoomOnAnotherVersionOpensNoConnection() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "Team", size: 3, nickname: "Sam")
        let joiner = star.coordinators[1]
        star.transports[1].onEvent?(.roomsChanged([RoomAdvert(id: "room", label: "Team", size: 3, hostNickname: "Sam",
                                                               protocolVersion: CravageCore.protocolVersion + 1)]))
        joiner.join(roomID: "room", nickname: "Alex")
        star.flush()
        XCTAssertEqual(star.transports[1].connectionAttempts, 0)
        XCTAssertEqual(joiner.engine.phase, .idle)
        XCTAssertTrue(star.coordinators[0].engine.pendingJoiners.isEmpty)
    }

    /// The advert is unchecked, so it is not the only guard: a host whose messages carry another
    /// version sends the joiner back to the room list with the reason, rather than leaving them in
    /// a lobby that can only time out.
    func testAHostOnAnotherVersionSendsTheJoinerBackWithTheReason() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "Team", size: 3, nickname: "Sam")
        let joiner = star.coordinators[1]
        joiner.browse()
        joiner.join(roomID: "room", nickname: "Alex")
        star.flush()
        XCTAssertEqual(joiner.engine.phase, .lobby)
        XCTAssertFalse(joiner.leftIncompatibleRoom)
        star.transports[1].onEvent?(.received(Data("{\"v\":\(CravageCore.protocolVersion + 1)}".utf8), from: .host))
        XCTAssertEqual(joiner.engine.phase, .idle)
        XCTAssertTrue(joiner.leftIncompatibleRoom)
        XCTAssertEqual(Screen(joiner, idle: .join), .join)

        joiner.join(roomID: "room", nickname: "Alex")
        XCTAssertFalse(joiner.leftIncompatibleRoom, "a new attempt starts without the old reason")
    }

    /// Only a joiner waiting in a lobby leaves on its host's version: a host refuses a joiner's
    /// message from another version as before and keeps its room open.
    func testAHostKeepsItsRoomWhenAJoinerSpeaksAnotherVersion() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        star.transports[0].onEvent?(.received(Data("{\"v\":\(CravageCore.protocolVersion + 1)}".utf8), from: PeerID(1)))
        XCTAssertEqual(host.engine.phase, .lobby)
        XCTAssertFalse(host.leftIncompatibleRoom)
        XCTAssertEqual(star.transports[0].hosting?.size, 3)
    }

    /// Once the round has started, a stray message in another version is refused and the round
    /// carries on: the lobby is the only place where it means the room cannot work.
    func testAMessageInAnotherVersionDoesNotEndAStartedRound() async {
        let star = await lockedRoom()
        let joiner = star.coordinators[1]
        let phase = joiner.engine.phase
        XCTAssertNotEqual(phase, .lobby)
        star.transports[1].onEvent?(.received(Data("{\"v\":\(CravageCore.protocolVersion + 1)}".utf8), from: .host))
        XCTAssertEqual(joiner.engine.phase, phase)
        XCTAssertFalse(joiner.leftIncompatibleRoom)
    }

    /// A malformed message in the current version is refused as before and does not end the join.
    func testAMalformedMessageInThisVersionDoesNotEndTheJoin() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "Team", size: 3, nickname: "Sam")
        let joiner = star.coordinators[1]
        joiner.join(roomID: "room", nickname: "Alex")
        star.flush()
        star.transports[1].onEvent?(.received(Data("{\"v\":\(CravageCore.protocolVersion)}".utf8), from: .host))
        XCTAssertEqual(joiner.engine.phase, .lobby)
        XCTAssertFalse(joiner.leftIncompatibleRoom)
    }

    /// The review found a refusal from one action still on screen as the answer to the next.
    func testAUserActionForgetsTheLastRefusal() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 4, nickname: "Sam")
        XCTAssertEqual(host.lastRejection, .notEntitled)

        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        XCTAssertNil(host.lastRejection, "an old refusal was still showing after a new action")
        XCTAssertEqual(host.engine.phase, .lobby)
    }

    /// `createRoom` clears the refusal in its own body, so it cannot show that the shared
    /// user-action path does. This drives a refusal and then an action that goes through that path.
    func testAnActionRoutedThroughTheEngineAlsoForgetsTheLastRefusal() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        host.start(generation: host.engine.generation)
        XCTAssertEqual(host.lastRejection, .notEnoughPeople)

        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        let pending = host.engine.pendingJoiners[0]
        host.admit(pending.verifyingKey, generation: host.engine.generation)
        XCTAssertNil(host.lastRejection, "an old refusal survived a new action")
        XCTAssertEqual(host.engine.admittedNicknames, ["Alex"], "and the action itself went through")
    }

    /// Found in the review of 2026-09-24: every engine refusal landed in `lastRejection`, including
    /// ones caused by another phone's message, so a screen could show "This round can't be
    /// restarted" as though it answered a tap nobody made (a late agreement after a partial result
    /// does exactly this). A refusal shown to the person must come from the person's own action.
    func testAPeerMessageRefusalIsNotShownAsTheAnswerToATap() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        let stray = Envelope.signed(action: .roomcodeConfirm, session: host.engine.session!, party: "A",
                                    content: "x", key: SigningKey()).encoded()
        star.transports[0].onEvent?(.received(stray, from: PeerID(1)))
        XCTAssertNil(host.lastRejection, "another phone's refused message was shown as the answer to a tap")
        XCTAssertEqual(host.lastPeerRejection, .wrongPhase, "diagnostics still record it")
    }

    /// Review 2026-09-24, finding 1: a refusal belongs to the screen it answered. Start was
    /// refused in the lobby; nobody tapped again; the lobby timed out. The failed screen must not
    /// then report "A restart needs at least 3 people" for a restart nobody tried.
    func testARefusalDoesNotFollowTheRoundOntoTheNextScreen() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        host.start(generation: host.engine.generation)
        XCTAssertEqual(host.lastRejection, .notEnoughPeople)
        await star.clock.advance(ms: 600_000)
        XCTAssertEqual(host.engine.phase, .failed(.timeout(.lobby)))
        XCTAssertNil(host.lastRejection, "a lobby refusal was carried onto the failed screen")
    }

    /// The diagnostics line about another phone's refused message belongs to the room it came from.
    func testLeavingForgetsTheLastRefusedMessage() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        star.transports[0].onEvent?(.received(Data("junk".utf8), from: PeerID(1)))
        XCTAssertNotNil(host.lastPeerRejection)
        host.leave()
        XCTAssertNil(host.lastPeerRejection)
    }

    func testAnActionThatIsRefusedAgainReportsTheNewRefusal() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        host.start(generation: host.engine.generation)
        XCTAssertEqual(host.lastRejection, .notEnoughPeople, "a real refusal must still reach the screen")
    }

    /// A phone in a started round has no use for the room list, and every extra multicast is noise
    /// on the Wi-Fi the round runs over.
    func testBrowsingStopsOnceTheRoundStarts() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].browse()
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        XCTAssertTrue(star.transports[1].browsing, "a joiner waiting in the lobby still looks for rooms")

        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        XCTAssertEqual(star.coordinators[1].engine.phase, .confirming)
        XCTAssertFalse(star.transports[1].browsing, "the joiner kept browsing inside the round")
        XCTAssertFalse(star.transports[2].browsing)
    }

    /// Decision 2026-09-24: once the round starts the room leaves the nearby list, so a
    /// latecomer is not shown a room that will only turn them away with "Lost the connection". It
    /// stays hidden through a restart, which only takes back phones that are already connected.
    func testTheRoomIsHiddenOnceTheRoundStarts() async {
        let star = FakeStar(phones: 4, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        XCTAssertTrue(star.transports[0].advertising, "a room waiting for people must be visible")
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        XCTAssertTrue(star.transports[0].advertising)

        host.start(generation: host.engine.generation)
        star.flush()
        XCTAssertEqual(host.engine.phase, .confirming)
        XCTAssertFalse(star.transports[0].advertising, "a started round was still listed nearby")
        star.coordinators[3].browse()
        XCTAssertTrue(star.coordinators[3].rooms.isEmpty, "a latecomer was shown a started round")

        host.restart(generation: host.engine.generation)
        star.flush()
        XCTAssertFalse(star.transports[0].advertising, "a restart listed the room again")
    }

    func testUnlockedHostOpensAnEightPersonRoom() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: true))
        await star.coordinators[0].createRoom(label: "Team", size: 8, nickname: "Sam")
        XCTAssertEqual(star.coordinators[0].engine.phase, .lobby)
        XCTAssertEqual(star.transports[0].hosting?.size, 8)
    }

    /// PLAN.md: an unlock that changes during a round leaves that round alone, and the next room
    /// asks again. Here a refund lands while a four-person room is filling.
    func testAnUnlockLostDuringARoomLetsItFinishButTheNextRoomAsksAgain() async {
        let entitlement = FakeEntitlement(unlocked: true)
        let star = FakeStar(phones: 4, entitlement: entitlement)
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 4, nickname: "Sam")
        entitlement.unlocked = false
        for (index, name) in [(1, "Alex"), (2, "Dee"), (3, "Kim")] {
            star.coordinators[index].browse()
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        for pending in host.engine.pendingJoiners { host.admit(pending.verifyingKey, generation: host.engine.generation) }
        host.start(generation: host.engine.generation)
        star.flush()
        XCTAssertEqual(host.engine.roster?.size, 4, "the room that was open when the unlock went keeps its size")
        host.leave()
        await host.createRoom(label: "Team", size: 4, nickname: "Sam")
        XCTAssertEqual(host.lastRejection, .notEntitled, "the next room asks the store again")
        XCTAssertEqual(entitlement.asked, 2)
    }

    func testDoubleTapOnNewRoomWhileTheStoreAnswersIsOneRoom() async {
        let entitlement = FakeEntitlement(unlocked: true)
        entitlement.holdAnswer = true
        let star = FakeStar(phones: 1, entitlement: entitlement)
        let host = star.coordinators[0]
        let first = Task { await host.createRoom(label: "Team", size: 5, nickname: "Sam") }
        for _ in 0..<10 { await Task.yield() }
        await host.createRoom(label: "Team", size: 5, nickname: "Sam")
        XCTAssertEqual(entitlement.asked, 1)
        entitlement.gate?.resume()
        await first.value
        XCTAssertEqual(host.engine.phase, .lobby)
        XCTAssertEqual(host.engine.generation, 1)
    }

    private func lockedRoom() async -> FakeStar {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].browse()
            XCTAssertEqual(star.coordinators[index].rooms.first?.label, "Annual bonus")
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        let host = star.coordinators[0]
        for pending in host.engine.pendingJoiners { host.admit(pending.verifyingKey, generation: host.engine.generation) }
        host.start(generation: host.engine.generation)
        star.flush()
        return star
    }

    func testRepeatedJoinKeepsTheConnectionAndCanCompleteAdmission() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        let joiner = star.coordinators[1]
        await host.createRoom(label: "Team", size: 3, nickname: "Host")
        joiner.join(roomID: "room", nickname: "Alex")
        joiner.join(roomID: "room", nickname: "Alex")
        star.flush()
        XCTAssertEqual(host.engine.pendingJoiners.count, 1)

        // Repeat after the signed welcome has established the session, while awaiting admission.
        joiner.join(roomID: "room", nickname: "Alex")
        star.flush()
        XCTAssertEqual(star.transports[1].connectionAttempts, 1)

        star.coordinators[2].join(roomID: "room", nickname: "Dee")
        star.flush()
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        XCTAssertEqual(joiner.engine.phase, .confirming)
        star.coordinators.forEach { $0.leave() }
    }

    func testARealRoundCompletesThroughCoordinatorsOverTheFakeTransport() async {
        let star = await lockedRoom()
        for coordinator in star.coordinators { XCTAssertEqual(coordinator.engine.phase, .confirming) }
        for coordinator in star.coordinators { coordinator.confirmRoomCode(generation: coordinator.engine.generation) }
        star.flush()
        for (coordinator, text) in zip(star.coordinators, ["10", "20.5", "30"]) {
            XCTAssertNil(coordinator.submitFigure(text, generation: coordinator.engine.generation))
        }
        star.flush()
        for coordinator in star.coordinators {
            XCTAssertEqual(coordinator.engine.phase, .complete(.agreed))
            XCTAssertEqual(coordinator.engine.average, "20.17")
        }
        let record = star.coordinators[1].engine.record!
        XCTAssertNotNil(Transcript.make(from: record))
    }

    /// Check the code has a Leave as well as "The codes don't match". Leaving is not a dispute:
    /// the others are told a phone left, never that it saw a different code.
    func testLeavingAtTheCodeCheckIsNotADispute() async {
        for (leaver, confirmedFirst) in [(1, false), (1, true), (0, false), (0, true)] {
            let star = await lockedRoom()
            XCTAssertEqual(star.coordinators[leaver].engine.phase, .confirming)
            if confirmedFirst {
                star.coordinators[leaver].confirmRoomCode(generation: star.coordinators[leaver].engine.generation)
                star.flush()
            }
            star.coordinators[leaver].leave()
            star.flush()
            XCTAssertEqual(star.coordinators[leaver].engine.phase, .idle)
            for (index, other) in star.coordinators.enumerated() where index != leaver {
                guard case let .failed(reason) = other.engine.phase else {
                    return XCTFail("phone \(index) is still in \(other.engine.phase) after phone \(leaver) left")
                }
                switch reason {
                case .peerLeft, .connectionLost, .aborted(.peerLeft), .aborted(.hostLeft): break
                default: XCTFail("phone \(index) was told \(reason), not that a phone left")
                }
                XCTAssertNil(other.engine.record, "no result without every share")
            }
        }
    }

    func testAFigureThatDoesNotParseIsReportedInlineAndSendsNothing() async {
        let star = await lockedRoom()
        let joiner = star.coordinators[1]
        let sentBefore = star.transports[1].sentCount
        XCTAssertEqual(joiner.submitFigure("1,000", generation: joiner.engine.generation), .invalidFormat)
        XCTAssertEqual(joiner.submitFigure("1000000000000", generation: joiner.engine.generation), .outOfDomain)
        XCTAssertEqual(star.transports[1].sentCount, sentBefore)
        XCTAssertNil(joiner.engine.frozenFigure)
    }

    /// Deadlines fire from the coordinator's own clock, with no user action.
    func testTheCoordinatorTicksTheEngineWhenADeadlinePasses() async {
        let star = await lockedRoom()
        await star.clock.advance(ms: 59_999)
        XCTAssertEqual(star.coordinators[0].engine.phase, .confirming)
        await star.clock.advance(ms: 1)
        star.flush()
        for coordinator in star.coordinators {
            guard case .failed = coordinator.engine.phase else { return XCTFail("\(coordinator.engine.phase)") }
        }
    }

    /// Regression gate: a transport failure mid-round cleans up keys, figures and deadlines.
    func testATransportFailureMidRoundCleansUpEverywhere() async {
        let star = await lockedRoom()
        for coordinator in star.coordinators { coordinator.confirmRoomCode(generation: coordinator.engine.generation) }
        star.flush()
        star.coordinators[0].submitFigure("5", generation: star.coordinators[0].engine.generation)
        star.flush()
        star.drop(2)
        star.flush()
        XCTAssertEqual(star.coordinators[0].engine.phase, .failed(.peerLeft(star.coordinators[2].engine.myLetter)))
        XCTAssertEqual(star.coordinators[1].engine.phase, .failed(.aborted(.peerLeft)))
        XCTAssertEqual(star.coordinators[2].engine.phase, .failed(.connectionLost))
        for coordinator in star.coordinators {
            XCTAssertNil(coordinator.engine.maskKey)
            XCTAssertNil(coordinator.engine.frozenFigure)
            XCTAssertNil(coordinator.engine.nextDeadline)
        }
    }

    /// Review finding 8: Leave while the store is answering must not open the room afterwards.
    func testLeaveDuringTheStoreCheckOpensNothing() async {
        let entitlement = FakeEntitlement(unlocked: true)
        entitlement.holdAnswer = true
        let star = FakeStar(phones: 1, entitlement: entitlement)
        let host = star.coordinators[0]
        let creating = Task { await host.createRoom(label: "Team", size: 5, nickname: "Sam") }
        for _ in 0..<10 { await Task.yield() }
        host.leave()
        entitlement.gate?.resume()
        await creating.value
        XCTAssertEqual(host.engine.phase, .idle)
        XCTAssertNil(star.transports[0].hosting)
    }

    /// Review finding 10: a listener that fails closes the room instead of leaving the host waiting.
    func testAFailedListenerClosesTheRoom() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "L", size: 3, nickname: "Sam")
        XCTAssertEqual(host.engine.phase, .lobby)
        star.transports[0].onEvent?(.hostingFailed(.localNetworkDenied))
        XCTAssertEqual(host.engine.phase, .idle)
        XCTAssertEqual(host.problem, .localNetworkDenied)
        XCTAssertNil(star.transports[0].hosting)
    }

    /// iOS can fail the first search before the person has answered the Local Network prompt. Once
    /// they allow it and a room is found, the Join screen shows the room without a Retry.
    func testAFoundRoomClearsAnEarlierDiscoveryError() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        let joiner = star.coordinators[1]
        joiner.browse()
        star.transports[1].onEvent?(.discoveryFailed(.localNetworkDenied))
        XCTAssertEqual(joiner.problem, .localNetworkDenied)
        star.transports[1].onEvent?(.roomsChanged([]))
        XCTAssertEqual(joiner.problem, .localNetworkDenied, "an empty list does not show the search works")
        star.transports[1].onEvent?(.roomsChanged([RoomAdvert(id: "room", label: "Team", size: 3, hostNickname: "Sam",
                                                               protocolVersion: CravageCore.protocolVersion)]))
        XCTAssertNil(joiner.problem)
    }

    /// Non-goal pin: a failed listener's error is not cleared by rooms someone else is advertising.
    func testAFoundRoomDoesNotClearAHostingError() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "L", size: 3, nickname: "Sam")
        star.transports[0].onEvent?(.hostingFailed(.unavailable))
        star.transports[0].onEvent?(.roomsChanged([RoomAdvert(id: "other", label: "Team", size: 3, hostNickname: "Kim",
                                                               protocolVersion: CravageCore.protocolVersion)]))
        XCTAssertEqual(host.problem, .unavailable)
    }

    /// A failed listener after a discovery error is the error that stands; a room found later does
    /// not clear it.
    func testAHostingErrorAfterADiscoveryErrorIsNotClearedByAFoundRoom() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let phone = star.coordinators[0]
        phone.browse()
        star.transports[0].onEvent?(.discoveryFailed(.localNetworkDenied))
        await phone.createRoom(label: "L", size: 3, nickname: "Sam")
        star.transports[0].onEvent?(.hostingFailed(.unavailable))
        star.transports[0].onEvent?(.roomsChanged([RoomAdvert(id: "other", label: "Team", size: 3, hostNickname: "Kim",
                                                               protocolVersion: CravageCore.protocolVersion)]))
        XCTAssertEqual(phone.problem, .unavailable)
    }

    /// A discovery error belongs to the Join screen it was raised on. Leaving it (Back, then New
    /// room) must not show that error on the New room form as if the room had failed to open.
    func testLeavingForgetsADiscoveryError() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let phone = star.coordinators[0]
        phone.browse()
        star.transports[0].onEvent?(.discoveryFailed(.localNetworkDenied))
        phone.leave()
        XCTAssertNil(phone.problem)
    }

    func testLeavingStopsTheTransport() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "L", size: 3, nickname: "Sam")
        star.coordinators[0].leave()
        XCTAssertNil(star.transports[0].hosting)
        XCTAssertEqual(star.coordinators[0].engine.phase, .idle)
    }
}
