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
    /// The engine's refusal of the person's own last action, for the screen to explain.
    private(set) var lastRejection: Rejection?
    /// The engine's last refusal of another phone's message or a timer. Diagnostics only: it is
    /// never the answer to a tap, so no screen shows it (codebase review, 2026-09-24).
    private(set) var lastPeerRejection: Rejection?
    private(set) var isCreatingRoom = false
    private(set) var wasInterrupted = false
    /// Navigation/background cancellation also invalidates actions when no round generation changes.
    private(set) var actionEpoch = 0
    /// The round generation whose restart warning this person acknowledged. Kept here rather than
    /// in a view so the rule can be tested: an acknowledgement belongs to the round it was made in,
    /// so the next restart warns again (SPEC 13). Cleared by Leave, because `generation` is not
    /// strictly increasing across a leave and rejoin (the joiner's welcome decrements it once).
    private(set) var restartWarningAcknowledged: Int?

    @ObservationIgnored private let transport: RoundTransport
    @ObservationIgnored private let clock: RoundClock
    @ObservationIgnored private let entitlement: EntitlementProvider
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var browsing = false
    @ObservationIgnored private var advertising = false

    init(transport: RoundTransport, clock: RoundClock, entitlement: EntitlementProvider, deadlines: Deadlines = Deadlines()) {
        self.engine = RoundEngine(deadlines: deadlines)
        self.transport = transport
        self.clock = clock
        self.entitlement = entitlement
        transport.onEvent = { [weak self] event in self?.transportEvent(event) }
    }

    /// The round, read so that a SwiftUI view re-renders when it moves.
    ///
    /// `RoundEngine` is a plain class: reading `coordinator.engine` registers nothing with
    /// Observation, so a screen built on it would draw once and then never change. Touching the
    /// observable `revision` first registers the dependency, and `apply` bumps `revision` after
    /// every event. Screens read the round through here; tests read `engine` directly.
    var live: RoundEngine {
        _ = revision
        return engine
    }

    // MARK: - User actions

    /// New Room. A second tap while the entitlement check is running is one operation.
    func createRoom(label: String, size: Int, nickname: String) async {
        guard !isCreatingRoom, engine.phase == .idle else { return }
        lastRejection = nil
        let epochBefore = actionEpoch
        isCreatingRoom = true
        defer { if actionEpoch == epochBefore { isCreatingRoom = false } }
        let entitled = size > Roster.minimumSize ? await entitlement.hasVerifiedUnlock() : false
        guard engine.phase == .idle, actionEpoch == epochBefore else { return }
        apply(.createRoom(label: label, maxSize: size, nickname: nickname, entitled: entitled))
        if engine.phase == .lobby, engine.role == .host {
            transport.startHosting(label: label, size: size, hostNickname: nickname)
            advertising = true
        }
    }

    func browse() {
        problem = nil
        browsing = true
        transport.startBrowsing()
    }

    /// The person has read the restarted-round warning for the round they are in.
    func acknowledgeRestartWarning() {
        restartWarningAcknowledged = engine.generation
    }

    func join(roomID: String, nickname: String) {
        guard engine.phase == .idle else { return }
        lastRejection = nil
        apply(.joinRoom(nickname: nickname))
        guard engine.phase == .lobby, engine.role == .joiner else { return }
        transport.connect(to: roomID)
    }

    func admit(_ key: VerifyingKey, generation: Int) { act(.admit(key, generation: generation)) }
    func decline(_ key: VerifyingKey, generation: Int) { act(.decline(key, generation: generation)) }
    func start(generation: Int) { act(.start(generation: generation)) }
    func confirmRoomCode(generation: Int) { act(.confirmRoomCode(generation: generation)) }
    func restart(generation: Int) { act(.restart(generation: generation)) }
    func acceptRestart(generation: Int) { act(.acceptRestart(generation: generation)) }

    /// A user action forgets the last refusal first, so a screen never reports an old rejection as
    /// the answer to what the person just did.
    private func act(_ event: Event) {
        lastRejection = nil
        apply(event)
    }

    /// Parses exactly as the web app does; a parse error is shown inline and nothing is sent.
    @discardableResult
    func submitFigure(_ text: String, generation: Int) -> FixedPointError? {
        lastRejection = nil
        do {
            let figure = try FixedPoint.parseDecimalToFixed(text)
            apply(.submitFigure(figure, generation: generation))
            return nil
        } catch {
            return error as? FixedPointError ?? .invalidFormat
        }
    }

    func leave() {
        actionEpoch += 1
        isCreatingRoom = false
        wasInterrupted = false
        lastRejection = nil
        restartWarningAcknowledged = nil
        apply(.leave)
        transport.stopAll()
        browsing = false
        advertising = false
        rooms = []
    }

    /// Called synchronously when the scene enters the background, including phone lock.
    func appEnteredBackground() {
        // Invalidate even idle-screen work queued before it could enter createRoom.
        actionEpoch += 1
        guard isCreatingRoom || !engine.phase.isTerminalOrIdle || engine.restartOffer != nil else { return }
        leave()
        wasInterrupted = true
    }

    /// Seconds left on the phase deadline, for the countdown lines. Nil when nothing is waiting.
    /// Rounded up, so a countdown reads 1 until the moment it expires rather than resting on 0.
    func secondsRemaining(now: UInt64? = nil) -> Int? {
        guard let deadline = engine.nextDeadline else { return nil }
        let current = now ?? clock.nowMs()
        guard deadline > current else { return 0 }
        return Int((deadline - current + 999) / 1000)
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
                if event.isPersonAction { lastRejection = reason } else { lastPeerRejection = reason }
            }
        }
        revision += 1
        stopBrowsingOnceTheRoundStarts()
        stopAdvertisingOnceTheRoundStarts()
        scheduleTick()
    }

    /// A phone in a started round has no use for the room list, and every extra multicast is noise
    /// on the same Wi-Fi the round is running over. The connection it already holds is untouched.
    private func stopBrowsingOnceTheRoundStarts() {
        guard browsing, engine.phase != .idle, engine.phase != .lobby else { return }
        browsing = false
        transport.stopBrowsing()
    }

    /// Owner decision 2026-09-24: a started round leaves the nearby list and stays off it, restarts
    /// included, because a restart only takes back phones that are already connected.
    private func stopAdvertisingOnceTheRoundStarts() {
        guard advertising, engine.phase != .idle, engine.phase != .lobby else { return }
        advertising = false
        transport.stopAdvertising()
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

private extension Event {
    /// Something the person did, as opposed to the network or the clock.
    var isPersonAction: Bool {
        switch self {
        case .peerConnected, .received, .peerDisconnected, .tick: return false
        case .createRoom, .joinRoom, .admit, .decline, .start, .confirmRoomCode, .submitFigure, .restart,
             .acceptRestart, .leave: return true
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
