import Foundation
import Observation
import CravageCore

/// Drives CravageCore.RoundEngine for the UI: feeds it transport events, user actions and clock
/// ticks; carries out its effects on the transport; schedules the next tick. Holds no protocol
/// rules of its own beyond one: it asks the entitlement provider before creating a room larger
/// than three, and the engine enforces the answer (SPEC invariant 11).
///
/// User actions carry the generation the screen was showing; the engine drops stale ones.
@MainActor
@Observable
final class RoundCoordinator {
    let engine: RoundEngine
    /// Bumped after every event so views re-read the engine.
    private(set) var revision = 0
    private(set) var rooms: [RoomAdvert] = []
    private(set) var problem: TransportProblem?
    private(set) var lastRejection: Rejection?
    private(set) var isCreatingRoom = false

    @ObservationIgnored private let transport: RoundTransport
    @ObservationIgnored private let clock: RoundClock
    @ObservationIgnored private let entitlement: EntitlementProvider
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// Bumped by Leave, so an answer from the store that arrives afterwards opens nothing.
    @ObservationIgnored private var leaveCount = 0

    init(transport: RoundTransport, clock: RoundClock, entitlement: EntitlementProvider, deadlines: Deadlines = Deadlines()) {
        self.engine = RoundEngine(deadlines: deadlines)
        self.transport = transport
        self.clock = clock
        self.entitlement = entitlement
        transport.onEvent = { [weak self] event in self?.transportEvent(event) }
    }

    // MARK: - User actions

    /// New Room. A second tap while the entitlement check is running is one operation.
    func createRoom(label: String, size: Int, nickname: String) async {
        guard !isCreatingRoom, engine.phase == .idle else { return }
        isCreatingRoom = true
        defer { isCreatingRoom = false }
        let leavesBefore = leaveCount
        let entitled = size > Roster.minimumSize ? await entitlement.hasVerifiedUnlock() : false
        guard engine.phase == .idle, leaveCount == leavesBefore else { return }
        apply(.createRoom(label: label, maxSize: size, nickname: nickname, entitled: entitled))
        if engine.phase == .lobby, engine.role == .host {
            transport.startHosting(label: label, size: size, hostNickname: nickname)
        }
    }

    func browse() {
        problem = nil
        transport.startBrowsing()
    }

    func join(roomID: String, nickname: String) {
        apply(.joinRoom(nickname: nickname))
        guard engine.phase == .lobby, engine.role == .joiner else { return }
        transport.connect(to: roomID)
    }

    func admit(_ key: VerifyingKey, generation: Int) { apply(.admit(key, generation: generation)) }
    func decline(_ key: VerifyingKey, generation: Int) { apply(.decline(key, generation: generation)) }
    func start(generation: Int) { apply(.start(generation: generation)) }
    func confirmRoomCode(generation: Int) { apply(.confirmRoomCode(generation: generation)) }
    func restart(generation: Int) { apply(.restart(generation: generation)) }
    func acceptRestart(generation: Int) { apply(.acceptRestart(generation: generation)) }

    /// Parses exactly as the web app does; a parse error is shown inline and nothing is sent.
    @discardableResult
    func submitFigure(_ text: String, generation: Int) -> FixedPointError? {
        do {
            let figure = try FixedPoint.parseDecimalToFixed(text)
            apply(.submitFigure(figure, generation: generation))
            return nil
        } catch {
            return error as? FixedPointError ?? .invalidFormat
        }
    }

    func leave() {
        leaveCount += 1
        apply(.leave)
        transport.stopAll()
        rooms = []
    }

    // MARK: - Engine plumbing

    private func transportEvent(_ event: TransportEvent) {
        switch event {
        case let .roomsChanged(adverts):
            rooms = adverts
            revision += 1
        case let .discoveryFailed(problem):
            self.problem = problem
            revision += 1
        case let .hostingFailed(problem):
            // Nobody can reach a room whose listener failed: close it rather than wait out the lobby.
            if engine.role == .host, !engine.phase.isTerminalOrIdle {
                leave()
            }
            self.problem = problem
            revision += 1
        case let .peerConnected(peer):
            apply(.peerConnected(peer))
        case let .received(data, from):
            apply(.received(data, from: from))
        case let .peerDisconnected(peer):
            apply(.peerDisconnected(peer))
        }
    }

    private func apply(_ event: Event) {
        let effects = engine.handle(event, now: clock.nowMs())
        for effect in effects {
            switch effect {
            case let .send(data, to):
                transport.send(data, to: to)
            case let .disconnect(peer):
                transport.disconnect(peer)
            case let .rejected(reason):
                lastRejection = reason
            }
        }
        revision += 1
        scheduleTick()
    }

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = nil
        guard let due = engine.nextTickDue else { return }
        tickTask = Task { [weak self, clock] in
            do { try await clock.sleep(untilMs: due) } catch { return }
            guard !Task.isCancelled else { return }
            self?.apply(.tick)
        }
    }
}

private extension Phase {
    var isTerminalOrIdle: Bool {
        switch self {
        case .idle, .complete, .failed: return true
        default: return false
        }
    }
}
