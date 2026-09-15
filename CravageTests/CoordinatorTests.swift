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
        var browsing = false
        var sentCount = 0
        var connectionAttempts = 0
        init(index: Int) { self.index = index }
        func startHosting(label: String, size: Int, hostNickname: String) { hosting = (label, size) }
        func startBrowsing() {
            browsing = true
            if let advert = star?.advert { onEvent?(.roomsChanged([advert])) }
        }
        func connect(to roomID: String) {
            connectionAttempts += 1
            star?.connect(joiner: index)
        }
        func send(_ data: Data, to peer: PeerID) { sentCount += 1; star?.enqueue(from: index, to: peer, data) }
        func disconnect(_ peer: PeerID) { star?.drop(index == 0 ? peer.raw : index) }
        func stopAll() { hosting = nil; browsing = false }
    }

    let transports: [Transport]
    let clock = FakeClock()
    var coordinators: [RoundCoordinator] = []
    var connected: Set<Int> = []
    private var queue: [(to: Int, event: TransportEvent)] = []

    var advert: RoomAdvert? {
        guard let hosting = transports[0].hosting else { return nil }
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

    func testUnlockedHostOpensAnEightPersonRoom() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: true))
        await star.coordinators[0].createRoom(label: "Team", size: 8, nickname: "Sam")
        XCTAssertEqual(star.coordinators[0].engine.phase, .lobby)
        XCTAssertEqual(star.transports[0].hosting?.size, 8)
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

    /// Retro gate: a transport failure mid-round cleans up keys, figures and deadlines.
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

    func testLeavingStopsTheTransport() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "L", size: 3, nickname: "Sam")
        star.coordinators[0].leave()
        XCTAssertNil(star.transports[0].hosting)
        XCTAssertEqual(star.coordinators[0].engine.phase, .idle)
    }
}
