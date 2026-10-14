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
    /// The problem came from discovery, so a room found later shows the search works again.
    private var problemIsDiscovery = false
    /// The engine's refusal of the person's own last action, for the screen to explain.
    private(set) var lastRejection: Rejection?
    /// The engine's last refusal of another phone's message or a timer. Diagnostics only: it is
    /// never the answer to a tap, so no screen shows it (codebase review, 2026-09-24).
    private(set) var lastPeerRejection: Rejection?
    private(set) var isCreatingRoom = false
    /// This phone left a room it had joined because the host's messages were from another protocol
    /// version. The Join screen says so; the next join or Leave clears it.
    private(set) var leftIncompatibleRoom = false
    private(set) var wasInterrupted = false
    /// Navigation/background cancellation also invalidates actions when no round generation changes.
    private(set) var actionEpoch = 0
    /// The round generation whose restart warning this person acknowledged. Kept here rather than
    /// in a view so the rule can be tested: an acknowledgement belongs to the round it was made in,
    /// so the next restart warns again (SPEC 13). Cleared by Leave, because `generation` is not
    /// strictly increasing across a leave and rejoin (the joiner's welcome decrements it once).
    private(set) var restartWarningAcknowledged: Int?
    /// The round this phone was last in, taken as it left. Diagnostics only.
    private(set) var lastRound: LastRound?

    @ObservationIgnored private let transport: RoundTransport
    @ObservationIgnored private let clock: RoundClock
    @ObservationIgnored private let entitlement: EntitlementProvider
    @ObservationIgnored private let keepScreenAwake: @MainActor (Bool) -> Void
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var listingOpen = false
    // For `lastRound`: the since-launch failure count when the room was entered, when the roster
    // last locked, and when this phone's own share was queued after that.
    @ObservationIgnored private var sendFailuresAtEntry = 0
    @ObservationIgnored private var rosterLockedMs: UInt64?
    @ObservationIgnored private var ownShareMs: UInt64?
    @ObservationIgnored private var listenerFailure: TransportProblem?

    init(transport: RoundTransport, clock: RoundClock, entitlement: EntitlementProvider, deadlines: Deadlines = Deadlines(),
         keepScreenAwake: @escaping @MainActor (Bool) -> Void = ScreenAwake.keep) {
        self.engine = RoundEngine(deadlines: deadlines)
        self.transport = transport
        self.clock = clock
        self.entitlement = entitlement
        self.keepScreenAwake = keepScreenAwake
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
            // A listener that failed at once has already closed the room through `leave`.
            listingOpen = engine.phase == .lobby
        }
    }

    /// From the Join screen only, never in a room: the transport's `startBrowsing` marks the work of
    /// any earlier start as stale, so a room's connections would go unreported.
    func browse() {
        problem = nil
        problemIsDiscovery = false
        transport.startBrowsing()
    }

    /// The person has read the restarted-round warning for the round they are in.
    func acknowledgeRestartWarning() {
        restartWarningAcknowledged = engine.generation
    }

    func join(roomID: String, nickname: String) {
        guard engine.phase == .idle else { return }
        // A room listed on another version would refuse every message; no connection is opened.
        if let advert = rooms.first(where: { $0.id == roomID }), !advert.isCompatible { return }
        lastRejection = nil
        leftIncompatibleRoom = false
        apply(.joinRoom(nickname: nickname))
        guard engine.phase == .lobby, engine.role == .joiner else { return }
        transport.connect(to: roomID)
    }

    func admit(_ key: VerifyingKey, generation: Int) { act(.admit(key, generation: generation)) }
    func decline(_ key: VerifyingKey, generation: Int) { act(.decline(key, generation: generation)) }
    func start(generation: Int) { act(.start(generation: generation)) }
    func confirmRoomCode(generation: Int) { act(.confirmRoomCode(generation: generation)) }
    func codesDiffer(generation: Int) { act(.codesDiffer(generation: generation)) }
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
        rememberTheRound()
        actionEpoch += 1
        isCreatingRoom = false
        wasInterrupted = false
        lastRejection = nil
        lastPeerRejection = nil
        leftIncompatibleRoom = false
        restartWarningAcknowledged = nil
        problem = nil
        problemIsDiscovery = false
        apply(.leave)
        // The one place in a round the registration goes and the search for rooms stops. Decision
        // 2026-10-13 replaces the 2026-09-24 one to stop both when the roster locks: a link over
        // peer-to-peer Wi-Fi went silent about a second after that (device report), and a device
        // run that stopped neither had no stall. Which of the two mattered is not known.
        listingOpen = false
        transport.stopAll()
        rooms = []
    }

    /// Called synchronously when the scene enters the background, including phone lock.
    func appEnteredBackground() {
        // Invalidate even idle-screen work queued before it could enter createRoom.
        actionEpoch += 1
        guard isCreatingRoom || !engine.phase.isTerminalOrIdle || engine.restartOffer != nil else {
            // A finished round keeps its result for sharing. Its room stays registered and its
            // joiners keep looking until Leave, so a restart once the phone is unlocked runs like
            // any other round (decision 2026-10-13); the closed listing names nothing meanwhile.
            // The Join screen's own search carries on too.
            return
        }
        leave()
        wasInterrupted = true
    }

    /// Failed sends since launch, for the diagnostics report.
    var sendFailures: Int { transport.sendFailures }

    /// Taken before Leave resets the engine and the transport forgets its connections.
    private func rememberTheRound() {
        guard engine.role != nil else { return }
        let now = clock.nowMs()
        lastRound = LastRound(
            role: engine.role, phase: engine.phase, generation: engine.generation,
            parties: engine.roster?.size ?? 0,
            confirmed: engine.roster == nil ? 0 : engine.confirmedLetters.count,
            sharesIn: engine.roster == nil ? 0 : engine.sharesReceived.count,
            sendFailures: max(0, transport.sendFailures - sendFailuresAtEntry),
            lastRefusedMessage: lastPeerRejection,
            secondsSinceRosterLocked: rosterLockedMs.map { Self.seconds(from: $0, to: now) },
            secondsToOwnShare: rosterLockedMs.flatMap { locked in ownShareMs.map { Self.seconds(from: locked, to: $0) } },
            links: transport.linkLog,
            listenerFailure: listenerFailure,
            registration: engine.role == .host ? transport.registrationCounts : nil)
        rosterLockedMs = nil
        ownShareMs = nil
        listenerFailure = nil
    }

    /// This phone's own share is in the round's set, which happens only when it is queued to send.
    private var ownShareMade: Bool {
        engine.myLetter.map { engine.sharesReceived.contains($0) } ?? false
    }

    private static func seconds(from start: UInt64, to end: UInt64) -> Int {
        end > start ? Int((end - start) / 1000) : 0
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
            // A waiting browser delivers results once it moves to ready (Network.framework
            // browser.h); the transport reports a policy-denied wait as a discovery error. That
            // the wait comes from an unanswered Local Network prompt is inferred, not documented.
            // A room found since shows the search works; an empty list shows nothing.
            if problemIsDiscovery, !adverts.isEmpty {
                problem = nil
                problemIsDiscovery = false
            }
            revision += 1
        case let .discoveryFailed(problem):
            self.problem = problem
            problemIsDiscovery = true
            revision += 1
        case let .hostingFailed(problem):
            // Nobody can reach a room whose listener failed: close a room still taking people rather
            // than wait out the lobby. Once the roster has locked nobody new is needed (a restart
            // takes back only phones already connected), so the round goes on and its report says so.
            if engine.role == .host, engine.phase == .lobby, engine.startNeedsFullRoom {
                leave()
            } else if engine.role == .host {
                listenerFailure = problem
            }
            self.problem = problem
            problemIsDiscovery = false
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
        let phaseBefore = engine.phase
        let ownShareBefore = ownShareMade
        let effects = engine.handle(event, now: clock.nowMs())
        if phaseBefore == .idle, engine.phase != .idle { sendFailuresAtEntry = transport.sendFailures }
        // Every lock, restarts included, starts the clock for this round's timings again.
        if engine.phase == .revealing, phaseBefore != .revealing {
            rosterLockedMs = clock.nowMs()
            ownShareMs = nil
        }
        // A figure typed early is only held until every phone has confirmed the code. The share is
        // queued in the step that adds it to the engine's set, which can also complete the set and
        // pass through sharing within the same step (device report 2026-10-11), so the set is what is read.
        if ownShareMade, !ownShareBefore { ownShareMs = clock.nowMs() }
        // A refusal answers a tap on the screen it was made on. When the network or the clock
        // moves the round to another screen, the refusal stays behind (review 2026-09-24).
        if !event.isPersonAction, engine.phase != phaseBefore { lastRejection = nil }
        var hostOnAnotherVersion = false
        for effect in effects {
            switch effect {
            case let .send(data, to):
                transport.send(data, to: to)
            case let .disconnect(peer):
                transport.disconnect(peer)
            case let .rejected(reason):
                if event.isPersonAction { lastRejection = reason } else { lastPeerRejection = reason }
                if case .message(.unsupportedVersion) = reason, case .received(_, from: .host) = event,
                   engine.role == .joiner, engine.phase == .lobby {
                    hostOnAnotherVersion = true
                }
            }
        }
        revision += 1
        scheduleTick()
        closeTheListingOnceTheRoomTakesNobodyNew()
        keepTheScreenAwakeWhileTheRoomCanGoOn()
        // The advert claimed this version, but the host speaks another: every message would be
        // refused, so the lobby could only time out. Leave now and say why.
        if hostOnAnotherVersion {
            leave()
            leftIncompatibleRoom = true
        }
    }

    /// Decision 2026-10-14: a host locked for about 10 seconds lost its connections on a device run,
    /// with Wi-Fi on and off, and Auto-Lock locks a phone left alone. That ends an unfinished round
    /// and leaves Run again with nobody connected. So while something more can happen in the room
    /// (`RoundEngine.roomCanGoOn`), the screen is kept from going to sleep on its own; once nothing
    /// can, it may sleep again, as Apple asks of the setting. Set after every step rather than only
    /// on a change, so a reset by anything else is undone at the next one.
    private func keepTheScreenAwakeWhileTheRoomCanGoOn() {
        keepScreenAwake(engine.roomCanGoOn)
    }

    /// Decision 2026-10-13: a room that takes nobody new, started or not, stays registered (see
    /// `leave`) but closes its listing, so nearby phones leave it off their lists and it no longer
    /// names the room or the host. Restarts keep it closed: they take back only phones already
    /// connected.
    private func closeTheListingOnceTheRoomTakesNobodyNew() {
        guard listingOpen, engine.phase != .idle, engine.phase != .lobby else { return }
        listingOpen = false
        transport.closeListing()
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

/// What happened to a round, kept after leaving it: Copy diagnostics is in Settings, which is only
/// reachable after Leave, and Leave resets the engine (device reports 2026-10-04 and 2026-10-09).
/// Counts, durations and fixed states only, so it can go into a support report.
struct LastRound {
    var role: Role?
    var phase: Phase
    var generation: Int
    var parties: Int
    var confirmed: Int
    var sharesIn: Int
    /// Sends that failed between entering the room and leaving it.
    var sendFailures: Int
    var lastRefusedMessage: Rejection?
    /// From the roster locking to leaving. Nil when the roster never locked.
    var secondsSinceRosterLocked: Int?
    /// From the roster locking to this phone's own share being queued. Nil when it never was.
    var secondsToOwnShare: Int?
    /// Read when the report is made, so it counts what Leave sent on the way out.
    var links: LinkLog
    /// Host: the listener failed after the round no longer needed it, so the round went on.
    var listenerFailure: TransportProblem?
    /// Host: the room's registrations up to leaving, so before the one Leave removes.
    var registration: RegistrationCounts?
}

private extension Event {
    /// Something the person did, as opposed to the network or the clock.
    var isPersonAction: Bool {
        switch self {
        case .peerConnected, .received, .peerDisconnected, .tick: return false
        case .createRoom, .joinRoom, .admit, .decline, .start, .confirmRoomCode, .codesDiffer, .submitFigure, .restart,
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
