// RoundEngine: the sans-IO round state machine (PLAN.md "RoundEngine"; docs/SPEC.md section 3).
//
// `handle(_:now:)` takes one event and a monotonic clock reading in milliseconds, updates state,
// and returns effects for the transport. Nothing here performs IO, sleeps or spawns work, so every
// invariant is testable by delivering bytes through `handle(.received)`.
//
// Star topology: a joiner only talks to the host (PeerID.host); the host verifies each post-lock
// message and forwards it to every other roster peer. Rejections are diagnostic codes only: no
// figure, key, mask, name or label ever appears in an effect other than the signed bytes.

import Foundation

public struct PeerID: Hashable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    /// How a joiner addresses its single connection.
    public static let host = PeerID(-1)
    public var description: String { raw == -1 ? "host" : "peer\(raw)" }
}

public enum Role: Sendable { case host, joiner }

public enum Stage: Equatable, Sendable { case lobby, confirming, keyExchange, sharing, collectingConfirmations }

public enum FailureReason: Equatable, Sendable {
    case timeout(Stage)
    /// Host view: a roster member's connection closed (letter known after lock).
    case peerLeft(PartyLabel?)
    /// Joiner view: the connection to the host closed or errored.
    case connectionLost
    /// The host ended the round and said why.
    case aborted(Wire.AbortReason)
    /// A party sent two different contents for the same slot.
    case conflictingMessage(PartyLabel)
    /// A party signed under a different roster than ours.
    case rosterMismatch(PartyLabel?)
    case invalidRoster
    case declined
    /// The host restarted while this round was still running; a restart offer is waiting.
    case hostRestarted
}

public enum Outcome: Equatable, Sendable {
    case agreed
    /// These letters signed a different set of shares than this phone saw.
    case mismatch([PartyLabel])
    /// These letters did not sign agreement before the deadline.
    case partial(missing: [PartyLabel])
    /// Was agreed; then this letter's conflicting agreement signature arrived (SPEC invariant 7).
    case disputed(PartyLabel)
}

public enum Phase: Equatable, Sendable {
    case idle
    case lobby
    /// Roster locked; collecting roomcode_confirm from everyone.
    case confirming
    /// Everyone confirmed the code; waiting for this phone's figure.
    case keyExchange
    /// This phone's share is sent; collecting the others.
    case sharing
    /// All shares in and summed; collecting result_confirm from everyone.
    case collectingConfirmations
    case complete(Outcome)
    case failed(FailureReason)

    var isTerminal: Bool {
        switch self {
        case .complete, .failed: return true
        default: return false
        }
    }

    var isLocked: Bool {
        switch self {
        case .confirming, .keyExchange, .sharing, .collectingConfirmations: return true
        default: return false
        }
    }
}

public enum Rejection: Equatable, Sendable {
    case message(MessageError)
    case wrongSession
    case notFromHost
    case unknownSender
    case wrongPhase
    case staleGeneration
    case invalidContent
    case duplicateKey
    case queueFull
    case flood
    case notEntitled
    case roomFull
    case notEnoughPeople
    case figureFrozen
    case outOfDomain
    case invalidInput
}

public enum Effect: Equatable, Sendable {
    case send(Data, to: PeerID)
    case disconnect(PeerID)
    case rejected(Rejection)
}

public enum Event: Sendable {
    /// Host: New Room. `entitled` is the coordinator's verified StoreKit state (SPEC invariant 11).
    case createRoom(label: String, maxSize: Int, nickname: String, entitled: Bool)
    /// Joiner: the connection to the chosen host is open.
    case joinRoom(nickname: String)
    /// Host: a new inbound connection.
    case peerConnected(PeerID)
    case received(Data, from: PeerID)
    /// Host: a joiner's connection closed. Joiner: PeerID.host closed or errored.
    case peerDisconnected(PeerID)
    case admit(VerifyingKey, generation: Int)
    case decline(VerifyingKey, generation: Int)
    case start(generation: Int)
    case confirmRoomCode(generation: Int)
    case submitFigure(Int64, generation: Int)
    case restart(generation: Int)
    /// Joiner: the person agreed to rejoin the host's restart (owner decision 2026-09-13: ask first).
    case acceptRestart(generation: Int)
    case leave
    case tick
}

public struct Deadlines: Equatable, Sendable {
    public var lobbyMs: UInt64
    public var confirmingMs: UInt64
    /// From everyone confirming the code to every share arriving: covers people typing figures.
    public var figureMs: UInt64
    /// From all shares arriving to every agreement signature arriving.
    public var confirmationsMs: UInt64
    /// Host: how long a new connection may stay silent before its hello, and how long a declined
    /// connection is left open to read its decline, before the host closes it.
    public var helloMs: UInt64

    public init(lobbyMs: UInt64 = 15 * 60_000, confirmingMs: UInt64 = 3 * 60_000,
                figureMs: UInt64 = 5 * 60_000, confirmationsMs: UInt64 = 20_000, helloMs: UInt64 = 15_000) {
        self.helloMs = helloMs
        self.lobbyMs = lobbyMs
        self.confirmingMs = confirmingMs
        self.figureMs = figureMs
        self.confirmationsMs = confirmationsMs
    }
}

public struct PendingJoiner: Equatable, Sendable {
    public let verifyingKey: VerifyingKey
    public let nickname: String
}

/// What a finished round keeps for display and transcript export.
public struct RoundRecord: Equatable, Sendable {
    /// Agreement can be withdrawn by a late conflicting confirmation. Existing exports are values.
    public fileprivate(set) var outcome: Outcome
    public let session: SessionID
    public let rosterHash: Data
    public let label: String
    public let parties: [Party]
    public let shares: [PartyLabel: String]
    public let shareSignatures: [PartyLabel: Signature]
    public let resultConfirmSignatures: [PartyLabel: Signature]
    /// roomcode_confirm signatures: over roster hash, label and keys, so they authenticate the label.
    public let roomcodeConfirmSignatures: [PartyLabel: Signature]
    public let sum: Int64

    public var boundSession: String { Envelope.boundSession(session, rosterHash: rosterHash) }
}

/// A host's restart waiting for this person's decision. Only what the UI needs to ask.
public struct RestartOffer: Equatable, Sendable {
    public let label: String
    public let size: Int
    fileprivate let session: SessionID
    fileprivate let nonce: String
    fileprivate let host: VerifyingKey
}

public final class RoundEngine {
    public static let maxConnections = 16
    public static let maxPending = 8
    /// Messages accepted from one connection in one generation before it is disconnected.
    /// Includes the host's relayed traffic on joiners; an honest eight-party round fits this budget.
    public static let maxMessagesPerPeer = 64

    public let deadlines: Deadlines

    // Public read-only state for the UI.
    public private(set) var role: Role?
    public private(set) var phase: Phase = .idle
    public private(set) var generation = 0
    public private(set) var label: String?
    public private(set) var maxSize = 0
    public private(set) var roster: Roster?
    public private(set) var myLetter: PartyLabel?
    public private(set) var nextDeadline: UInt64?
    public private(set) var sum: Int64?
    public private(set) var record: RoundRecord?
    /// SPEC invariant 13 (owner decision 2026-09-13): true for every round that replaced an earlier
    /// one, whoever is in it. A dishonest host can fake the same size and nicknames, so the warning
    /// cannot depend on the roster looking unchanged.
    public var restartWarningRequired: Bool { previousRound != nil && role != nil }
    /// Stronger copy: the new roster visibly has fewer people or different names than the last.
    public private(set) var restartRosterChanged = false
    /// Joiner: a restart the person has not yet accepted or declined.
    public private(set) var restartOffer: RestartOffer?
    public private(set) var localConfirmed = false
    public private(set) var lastIncompatibleVersion: Int?

    public var average: String? {
        guard let sum, let roster else { return nil }
        return FixedPoint.formatAverageFixed(sum, count: roster.size)
    }

    /// SPEC invariant 12: how many other physical phones should be showing the same code.
    public var otherPhonesExpected: Int {
        if let roster { return roster.size - 1 }
        return role == .host ? admitted.count : max(maxSize - 1, 0)
    }

    public var pendingJoiners: [PendingJoiner] {
        pending.map { PendingJoiner(verifyingKey: $0.key, nickname: $0.hello.nickname) }
    }

    public var admittedCount: Int { admitted.count }

    /// Host: the nicknames of everyone let into the room, in admission order. Party letters are not
    /// assigned until the roster locks, so the lobby has names and nothing else to show.
    /// Read-only; admission itself stays an engine decision.
    public var admittedNicknames: [String] { admitted.map(\.hello.nickname) }

    /// The earliest clock reading at which a `.tick` has work to do (a phase deadline or a
    /// connection to close). The app schedules its next tick no later than this.
    public var nextTickDue: UInt64? {
        ([nextDeadline].compactMap { $0 } + connectionDeadlines.values).min()
    }
    /// The letter the host holds, once the roster is locked: on a joiner the one carried by the
    /// welcome it verified, on the host its own. There are no letters before the lock.
    public var hostLetter: PartyLabel? {
        guard let roster else { return nil }
        if role == .host { return myLetter }
        guard let hostKey else { return nil }
        return roster.label(for: hostKey)
    }

    public var confirmedLetters: Set<PartyLabel> { Set(roomcodeConfirms.keys) }
    public var sharesReceived: Set<PartyLabel> { Set(shares.keys) }

    // Internal state (visible to @testable tests only).
    private(set) var session: SessionID?
    private(set) var nonce: String?
    private(set) var signingKey: SigningKey?
    private(set) var maskKey: MaskPrivateKey?
    private(set) var frozenFigure: Int64?
    private var nickname = ""
    private var entitled = false
    private var hostKey: VerifyingKey?

    private struct Joiner {
        let peer: PeerID
        let key: VerifyingKey
        let hello: Wire.Hello
        let signature: Signature
    }
    private var connected: Set<PeerID> = []
    private var pending: [Joiner] = []
    private var admitted: [Joiner] = []
    private var declinedPeers: Set<PeerID> = []
    /// Host: connections that must say hello (or, once declined, be gone) by this clock reading.
    private var connectionDeadlines: [PeerID: UInt64] = [:]
    private var messageCounts: [PeerID: Int] = [:]
    private var rosterPeers: [PartyLabel: PeerID] = [:]
    private var ownHelloSignature: Signature?
    /// Restart: connections from the replaced round, re-admitted automatically.
    private var carriedPeers: Set<PeerID> = []
    private var restartPending = false
    private var previousRound: (size: Int, nicknames: [String])?

    private var roomcodeConfirms: [PartyLabel: (content: String, signature: Signature)] = [:]
    private var shares: [PartyLabel: (content: String, signature: Signature)] = [:]
    private var resultConfirms: [PartyLabel: (content: String, signature: Signature)] = [:]
    private var sentShareGeneration: Int?
    private var myResultDigest: String?

    public init(deadlines: Deadlines = Deadlines()) {
        self.deadlines = deadlines
    }

    // MARK: - Entry point

    public func handle(_ event: Event, now: UInt64) -> [Effect] {
        var effects: [Effect] = []
        if let deadline = nextDeadline, now >= deadline {
            expire(now: now, into: &effects)
        }
        for (peer, deadline) in connectionDeadlines.sorted(by: { $0.key.raw < $1.key.raw }) where now >= deadline {
            connectionDeadlines[peer] = nil
            effects.append(.disconnect(peer))
        }
        switch event {
        case let .createRoom(label, maxSize, nickname, entitled):
            createRoom(label: label, maxSize: maxSize, nickname: nickname, entitled: entitled, now: now, into: &effects)
        case let .joinRoom(nickname):
            joinRoom(nickname: nickname, now: now, into: &effects)
        case let .peerConnected(peer):
            peerConnected(peer, now: now, into: &effects)
        case let .received(data, from):
            received(data, from: from, now: now, into: &effects)
        case let .peerDisconnected(peer):
            peerDisconnected(peer, now: now, into: &effects)
        case let .admit(key, generation):
            guard checkGeneration(generation, into: &effects) else { break }
            admit(key, now: now, into: &effects)
        case let .decline(key, generation):
            guard checkGeneration(generation, into: &effects) else { break }
            decline(key, now: now, into: &effects)
        case let .start(generation):
            guard checkGeneration(generation, into: &effects) else { break }
            start(now: now, into: &effects)
        case let .confirmRoomCode(generation):
            guard checkGeneration(generation, into: &effects) else { break }
            confirmRoomCode(now: now, into: &effects)
        case let .submitFigure(figure, generation):
            guard checkGeneration(generation, into: &effects) else { break }
            submitFigure(figure, now: now, into: &effects)
        case let .restart(generation):
            guard role == .host else { effects.append(.rejected(.wrongPhase)); break }
            guard checkGeneration(generation, into: &effects) else { break }
            restart(now: now, into: &effects)
        case let .acceptRestart(generation):
            guard checkGeneration(generation, into: &effects) else { break }
            acceptRestart(now: now, into: &effects)
        case .leave:
            leave(into: &effects)
        case .tick:
            break
        }
        return effects
    }

    /// Deadline arithmetic saturates: a clock near UInt64.max must never trap.
    private func after(_ now: UInt64, _ ms: UInt64) -> UInt64 {
        let (value, overflow) = now.addingReportingOverflow(ms)
        return overflow ? .max : value
    }

    private func checkGeneration(_ value: Int, into effects: inout [Effect]) -> Bool {
        guard value == generation else {
            effects.append(.rejected(.staleGeneration))
            return false
        }
        return true
    }

    // MARK: - Room creation and joining

    private func createRoom(label: String, maxSize: Int, nickname: String, entitled: Bool, now: UInt64,
                            into effects: inout [Effect]) {
        guard phase == .idle else { effects.append(.rejected(.wrongPhase)); return }
        guard RoomText.isValidLabel(label), RoomText.isValidNickname(nickname),
              (Roster.minimumSize...Roster.maximumSize).contains(maxSize) else {
            effects.append(.rejected(.invalidInput)); return
        }
        guard maxSize <= Roster.minimumSize || entitled else { effects.append(.rejected(.notEntitled)); return }
        role = .host
        self.nickname = nickname
        self.entitled = entitled
        self.maxSize = maxSize
        self.label = label
        beginSession(SessionID.random(), nonce: Wire.randomNonce(), now: now)
        let hello = Wire.Hello(mask: maskKey!.publicKey, nonce: nonce!, nickname: nickname)
        ownHelloSignature = signHello(hello)
    }

    private func joinRoom(nickname: String, now: UInt64, into effects: inout [Effect]) {
        guard phase == .idle else { effects.append(.rejected(.wrongPhase)); return }
        guard RoomText.isValidNickname(nickname) else { effects.append(.rejected(.invalidInput)); return }
        role = .joiner
        self.nickname = nickname
        generation += 1
        phase = .lobby
        nextDeadline = after(now, deadlines.lobbyMs)
    }

    /// Fresh keys, fresh session, fresh generation: every round and every restart.
    private func beginSession(_ newSession: SessionID, nonce newNonce: String, now: UInt64) {
        generation += 1
        session = newSession
        nonce = newNonce
        signingKey = SigningKey()
        maskKey = MaskPrivateKey()
        frozenFigure = nil
        roster = nil
        myLetter = nil
        sum = nil
        record = nil
        localConfirmed = false
        roomcodeConfirms = [:]
        shares = [:]
        resultConfirms = [:]
        sentShareGeneration = nil
        myResultDigest = nil
        pending = []
        admitted = []
        rosterPeers = [:]
        messageCounts = [:]
        ownHelloSignature = nil
        restartRosterChanged = false
        restartOffer = nil
        phase = .lobby
        nextDeadline = after(now, deadlines.lobbyMs)
    }

    private func signHello(_ hello: Wire.Hello) -> Signature {
        let key = signingKey!
        let canonical = CanonicalMessage(action: .pubkey, session: session!.hex, party: key.verifyingKey.base64, content: hello.content)
        return key.sign(canonical.string)
    }

    private func sendHello(into effects: inout [Effect]) {
        let hello = Wire.Hello(mask: maskKey!.publicKey, nonce: nonce!, nickname: nickname)
        let envelope = Envelope.signed(action: .pubkey, session: session!, party: signingKey!.verifyingKey.base64,
                                       content: hello.content, key: signingKey!)
        effects.append(.send(envelope.encoded(), to: .host))
    }

    // MARK: - Host: connections and admission

    private func peerConnected(_ peer: PeerID, now: UInt64, into effects: inout [Effect]) {
        guard role == .host, phase == .lobby, connected.count < RoundEngine.maxConnections else {
            effects.append(.disconnect(peer)); return
        }
        connected.insert(peer)
        connectionDeadlines[peer] = after(now, deadlines.helloMs)
        let welcome = Wire.Control.welcome(nonce: nonce!, label: label!, size: maxSize)
        effects.append(.send(control(welcome), to: peer))
    }

    private func control(_ message: Wire.Control) -> Data {
        Envelope.signed(action: .control, session: session!, party: Wire.hostParty, content: Wire.encode(message),
                        key: signingKey!).encoded()
    }

    private func hostReceivedHello(_ message: VerifiedMessage, from peer: PeerID, now: UInt64, into effects: inout [Effect]) {
        guard phase == .lobby else { effects.append(.rejected(.wrongPhase)); return }
        guard message.rosterHash == nil else { effects.append(.rejected(.invalidContent)); return }
        guard message.party == message.sender.base64 else { effects.append(.rejected(.unknownSender)); return }
        guard let hello = Wire.Hello.parse(message.content), hello.nonce == nonce else {
            effects.append(.rejected(.invalidContent)); return
        }
        let all = pending + admitted
        if let existing = all.first(where: { $0.key == message.sender }) {
            // First write wins: an identical hello again on the same link is a no-op.
            if existing.peer == peer && existing.hello == hello { return }
            effects.append(.rejected(.duplicateKey)); return
        }
        guard !all.contains(where: { $0.peer == peer }) else { effects.append(.rejected(.duplicateKey)); return }
        var points: Set<Data> = [signingKey!.verifyingKey.x963, maskKey!.publicKey.x963]
        for joiner in all { points.insert(joiner.key.x963); points.insert(joiner.hello.mask.x963) }
        guard message.sender.x963 != hello.mask.x963, !points.contains(message.sender.x963), !points.contains(hello.mask.x963) else {
            effects.append(.rejected(.duplicateKey)); return
        }
        let joiner = Joiner(peer: peer, key: message.sender, hello: hello, signature: message.signature)
        if restartPending, carriedPeers.contains(peer) {
            connectionDeadlines[peer] = nil
            admitted.append(joiner)
            lockIfRestartReady(now: now, into: &effects)
            return
        }
        guard pending.count < RoundEngine.maxPending else {
            effects.append(.rejected(.queueFull))
            effects.append(.disconnect(peer))
            return
        }
        connectionDeadlines[peer] = nil
        pending.append(joiner)
    }

    private func admit(_ key: VerifyingKey, now: UInt64, into effects: inout [Effect]) {
        guard role == .host, phase == .lobby, !restartPending else { effects.append(.rejected(.wrongPhase)); return }
        guard let index = pending.firstIndex(where: { $0.key == key }) else { effects.append(.rejected(.invalidInput)); return }
        guard admitted.count + 1 < maxSize else { effects.append(.rejected(.roomFull)); return }
        guard admitted.count + 2 <= Roster.minimumSize || entitled else { effects.append(.rejected(.notEntitled)); return }
        admitted.append(pending.remove(at: index))
    }

    private func decline(_ key: VerifyingKey, now: UInt64, into effects: inout [Effect]) {
        guard role == .host, phase == .lobby else { effects.append(.rejected(.wrongPhase)); return }
        guard let index = pending.firstIndex(where: { $0.key == key }) else { effects.append(.rejected(.invalidInput)); return }
        let joiner = pending.remove(at: index)
        declinedPeers.insert(joiner.peer)
        connectionDeadlines[joiner.peer] = after(now, deadlines.helloMs)
        effects.append(.send(control(.decline), to: joiner.peer))
    }

    private func start(now: UInt64, into effects: inout [Effect]) {
        guard role == .host, phase == .lobby else { effects.append(.rejected(.wrongPhase)); return }
        let size = admitted.count + 1
        guard size >= Roster.minimumSize else { effects.append(.rejected(.notEnoughPeople)); return }
        guard size <= maxSize else { effects.append(.rejected(.roomFull)); return }
        lock(now: now, into: &effects)
    }

    /// Restart: lock as soon as every still-connected participant of the replaced round is back.
    private func lockIfRestartReady(now: UInt64, into effects: inout [Effect]) {
        guard restartPending, phase == .lobby, carriedPeers.isSubset(of: Set(admitted.map(\.peer))),
              admitted.count + 1 >= Roster.minimumSize else { return }
        lock(now: now, into: &effects)
    }

    func signedHellosForTesting() -> [Wire.SignedHello] { signedHellos() }

    private func signedHellos() -> [Wire.SignedHello] {
        var entries = [Wire.SignedHello(vk: signingKey!.verifyingKey.base64, mask: maskKey!.publicKey.base64,
                                        nick: nickname, sig: ownHelloSignature!.base64)]
        for joiner in admitted {
            entries.append(Wire.SignedHello(vk: joiner.key.base64, mask: joiner.hello.mask.base64,
                                            nick: joiner.hello.nickname, sig: joiner.signature.base64))
        }
        return entries
    }

    /// Host: freeze the roster, send it to admitted peers, turn away everyone else.
    private func lock(now: UInt64, into effects: inout [Effect]) {
        let size = admitted.count + 1
        // SPEC invariant 11: the entitlement guard applies at lock too, whatever path got here.
        guard size <= Roster.minimumSize || entitled else { effects.append(.rejected(.notEntitled)); return }
        let entries = [RosterEntry(verifyingKey: signingKey!.verifyingKey, maskPublicKey: maskKey!.publicKey, nickname: nickname)]
            + admitted.map { RosterEntry(verifyingKey: $0.key, maskPublicKey: $0.hello.mask, nickname: $0.hello.nickname) }
        guard let locked = try? Roster(session: session!, label: label!, entries: entries) else {
            effects.append(.rejected(.invalidInput)); return
        }
        let data = control(.roster(signedHellos()))
        for joiner in pending {
            declinedPeers.insert(joiner.peer)
            connectionDeadlines[joiner.peer] = after(now, deadlines.helloMs)
            effects.append(.send(control(.decline), to: joiner.peer))
        }
        pending = []
        for joiner in admitted {
            effects.append(.send(data, to: joiner.peer))
            rosterPeers[locked.label(for: joiner.key)!] = joiner.peer
        }
        carriedPeers = []
        restartPending = false
        enterConfirming(locked, now: now)
    }

    private func enterConfirming(_ locked: Roster, now: UInt64) {
        roster = locked
        myLetter = locked.label(for: signingKey!.verifyingKey)
        if let previousRound {
            restartRosterChanged = locked.size < previousRound.size
                || locked.parties.map(\.nickname).sorted() != previousRound.nicknames
        }
        phase = .confirming
        nextDeadline = after(now, deadlines.confirmingMs)
    }

    // MARK: - Receiving

    private func received(_ data: Data, from peer: PeerID, now: UInt64, into effects: inout [Effect]) {
        guard let role else { effects.append(.rejected(.wrongPhase)); return }
        if role == .host {
            guard connected.contains(peer) else { return }
            if declinedPeers.contains(peer) { effects.append(.disconnect(peer)); return }
        } else if peer != .host {
            return
        }
        // Bound both roles before decoding or signature verification, including queued messages
        // after a disconnect request. Saturation keeps that queue from growing the counter forever.
        let count = messageCounts[peer] ?? 0
        guard count < RoundEngine.maxMessagesPerPeer else {
            effects.append(.rejected(.flood))
            effects.append(.disconnect(peer))
            return
        }
        messageCounts[peer] = count + 1
        let message: VerifiedMessage
        do {
            message = try Envelope.decodeAndVerify(data)
        } catch let error as MessageError {
            if case let .unsupportedVersion(version) = error { lastIncompatibleVersion = version }
            effects.append(.rejected(.message(error)))
            return
        } catch {
            effects.append(.rejected(.message(.malformed)))
            return
        }
        if role == .host {
            hostReceived(message, data: data, from: peer, now: now, into: &effects)
        } else {
            joinerReceived(message, now: now, into: &effects)
        }
    }

    private func hostReceived(_ message: VerifiedMessage, data: Data, from peer: PeerID, now: UInt64, into effects: inout [Effect]) {
        guard !isFailed else { return }
        guard message.session == session else { effects.append(.rejected(.wrongSession)); return }
        switch message.action {
        case .control:
            effects.append(.rejected(.notFromHost))
        case .pubkey:
            hostReceivedHello(message, from: peer, now: now, into: &effects)
        case .roomcodeConfirm, .share, .resultConfirm:
            guard let roster, phase.isLocked || phase == .complete(.agreed) else { effects.append(.rejected(.wrongPhase)); return }
            guard let letter = PartyLabel(message.party), roster.contains(letter),
                  roster.party(letter).verifyingKey == message.sender, rosterPeers[letter] == peer else {
                effects.append(.rejected(.unknownSender)); return
            }
            guard message.rosterHash == roster.rosterHash else {
                fail(.rosterMismatch(letter), now: now, into: &effects); return
            }
            let isNew = roundMessage(message, letter: letter, now: now, into: &effects)
            if isNew {
                for (other, otherPeer) in rosterPeers where other != letter {
                    effects.append(.send(data, to: otherPeer))
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func joinerReceived(_ message: VerifiedMessage, now: UInt64, into effects: inout [Effect]) {
        guard let hostKey else {
            // First contact: only a welcome, which establishes session and host key on trust;
            // the room code comparison is what checks it.
            guard phase == .lobby, message.action == .control, message.party == Wire.hostParty, message.rosterHash == nil,
                  case let .welcome(welcomeNonce, welcomeLabel, size)? = Wire.decodeControl(message.content) else {
                effects.append(.rejected(.wrongPhase)); return
            }
            self.hostKey = message.sender
            label = welcomeLabel
            maxSize = size
            let deadline = nextDeadline
            beginSession(message.session, nonce: welcomeNonce, now: now)
            generation -= 1  // joining was already this generation's user action
            nextDeadline = deadline
            sendHello(into: &effects)
            return
        }
        guard message.session == session else { effects.append(.rejected(.wrongSession)); return }
        switch message.action {
        case .control:
            guard message.sender == hostKey, message.party == Wire.hostParty else {
                effects.append(.rejected(.notFromHost)); return
            }
            guard let control = Wire.decodeControl(message.content) else { effects.append(.rejected(.invalidContent)); return }
            joinerControl(control, now: now, into: &effects)
        case .pubkey:
            effects.append(.rejected(.wrongPhase))
        case .roomcodeConfirm, .share, .resultConfirm:
            guard !isFailed else { return }
            guard let roster, phase.isLocked || phase == .complete(.agreed) else { effects.append(.rejected(.wrongPhase)); return }
            guard let letter = PartyLabel(message.party), roster.contains(letter),
                  roster.party(letter).verifyingKey == message.sender else {
                effects.append(.rejected(.unknownSender)); return
            }
            guard message.rosterHash == roster.rosterHash else {
                fail(.rosterMismatch(letter), now: now, into: &effects); return
            }
            _ = roundMessage(message, letter: letter, now: now, into: &effects)
        }
    }

    private func joinerControl(_ control: Wire.Control, now: UInt64, into effects: inout [Effect]) {
        switch control {
        case .welcome:
            effects.append(.rejected(.wrongPhase))
        case let .roster(entries):
            guard phase == .lobby, roster == nil else { effects.append(.rejected(.wrongPhase)); return }
            guard let locked = verifiedRoster(entries) else {
                fail(.invalidRoster, now: now, into: &effects)
                effects.append(.disconnect(.host))
                return
            }
            enterConfirming(locked, now: now)
        case .decline:
            guard phase == .lobby, roster == nil else { effects.append(.rejected(.wrongPhase)); return }
            fail(.declined, now: now, into: &effects)
            effects.append(.disconnect(.host))
        case let .abort(reason):
            guard !phase.isTerminal else { return }
            fail(.aborted(reason), now: now, into: &effects)
        case let .restart(newSession, newNonce, newLabel, size, newHost):
            guard phase != .lobby || roster != nil, newSession != session else {
                effects.append(.rejected(.wrongPhase)); return
            }
            if !phase.isTerminal { fail(.hostRestarted, now: now, into: &effects) }
            // Nothing is sent until the person agrees; the offer lapses with the host's restart lobby.
            restartOffer = RestartOffer(label: newLabel, size: size, session: newSession, nonce: newNonce, host: newHost)
            nextDeadline = after(now, deadlines.confirmingMs)
        }
    }

    /// Joiner: every entry's hello signature verifies under its own key for this session and
    /// nonce; the host and this phone are both present, with this phone's exact keys and name.
    private func verifiedRoster(_ entries: [Wire.SignedHello]) -> Roster? {
        guard entries.count <= maxSize else { return nil }
        var rosterEntries: [RosterEntry] = []
        for entry in entries {
            guard let key = try? VerifyingKey(base64: entry.vk), let mask = try? MaskPublicKey(base64: entry.mask),
                  RoomText.isValidNickname(entry.nick), let signature = try? Signature(base64: entry.sig) else { return nil }
            let hello = Wire.Hello(mask: mask, nonce: nonce!, nickname: entry.nick)
            let canonical = CanonicalMessage(action: .pubkey, session: session!.hex, party: key.base64, content: hello.content)
            guard key.verify(signature, message: canonical.string) else { return nil }
            rosterEntries.append(RosterEntry(verifyingKey: key, maskPublicKey: mask, nickname: entry.nick))
        }
        guard let locked = try? Roster(session: session!, label: label!, entries: rosterEntries),
              let me = locked.label(for: signingKey!.verifyingKey),
              locked.party(me).maskPublicKey == maskKey!.publicKey, locked.party(me).nickname == nickname,
              let hostKey, locked.label(for: hostKey) != nil else { return nil }
        return locked
    }

    // MARK: - Round messages (both roles)

    /// Applies a verified, roster-bound message. Returns true when it was new (and so worth
    /// forwarding); identical repeats return false.
    private func roundMessage(_ message: VerifiedMessage, letter: PartyLabel, now: UInt64, into effects: inout [Effect]) -> Bool {
        let signature = message.signature
        if case .complete(let outcome) = phase {
            // SPEC invariant 7: the only way out of a completed round is agreed -> disputed.
            guard outcome == .agreed, message.action == .resultConfirm, let existing = resultConfirms[letter] else { return false }
            if existing.content == message.content { return false }
            phase = .complete(.disputed(letter))
            record?.outcome = .disputed(letter)
            return true
        }
        guard letter != myLetter else { return false }
        switch message.action {
        case .roomcodeConfirm:
            if let existing = roomcodeConfirms[letter] {
                if existing.content == message.content { return false }
                fail(.conflictingMessage(letter), now: now, into: &effects); return false
            }
            guard message.content == Wire.roomcodeDigest(roster!) else {
                fail(.rosterMismatch(letter), now: now, into: &effects); return false
            }
            roomcodeConfirms[letter] = (message.content, signature)
            passBarrierIfReady(now: now, into: &effects)
            return true
        case .share:
            guard (try? ShareString.parse(message.content)) != nil else { effects.append(.rejected(.invalidContent)); return false }
            if let existing = shares[letter] {
                if existing.content == message.content { return false }
                fail(.conflictingMessage(letter), now: now, into: &effects); return false
            }
            shares[letter] = (message.content, signature)
            sumIfComplete(now: now, into: &effects)
            return true
        case .resultConfirm:
            guard message.content.utf8.count == 64, Hex.decode(message.content) != nil else {
                effects.append(.rejected(.invalidContent)); return false
            }
            if let existing = resultConfirms[letter] {
                if existing.content == message.content { return false }
                fail(.conflictingMessage(letter), now: now, into: &effects); return false
            }
            resultConfirms[letter] = (message.content, signature)
            resolveIfComplete(now: now)
            return true
        case .pubkey, .control:
            return false
        }
    }

    // MARK: - Local user actions

    private func confirmRoomCode(now: UInt64, into effects: inout [Effect]) {
        guard let roster, let myLetter, !phase.isTerminal, phase != .lobby, phase != .idle else {
            effects.append(.rejected(.wrongPhase)); return
        }
        if localConfirmed { return }
        localConfirmed = true
        let content = Wire.roomcodeDigest(roster)
        let envelope = Envelope.signed(action: .roomcodeConfirm, session: session!, rosterHash: roster.rosterHash,
                                       party: myLetter.letter, content: content, key: signingKey!)
        roomcodeConfirms[myLetter] = (content, try! Signature(base64: envelope.sig))
        send(envelope.encoded(), into: &effects)
        passBarrierIfReady(now: now, into: &effects)
    }

    private func submitFigure(_ figure: Int64, now: UInt64, into effects: inout [Effect]) {
        guard phase == .confirming || phase == .keyExchange || phase == .sharing || phase == .collectingConfirmations else {
            effects.append(.rejected(.wrongPhase)); return
        }
        guard figure.magnitude <= UInt64(FixedPoint.maxMagnitude) else { effects.append(.rejected(.outOfDomain)); return }
        if let frozenFigure {
            if frozenFigure != figure { effects.append(.rejected(.figureFrozen)) }
            return
        }
        guard sentShareGeneration != generation else { effects.append(.rejected(.figureFrozen)); return }
        frozenFigure = figure
        sendShareIfReady(now: now, into: &effects)
    }

    /// Own round message: a joiner sends it to the host; the host sends it to every roster peer.
    private func send(_ data: Data, into effects: inout [Effect]) {
        if role == .host {
            for peer in rosterPeers.sorted(by: { $0.key < $1.key }).map(\.value) {
                effects.append(.send(data, to: peer))
            }
        } else {
            effects.append(.send(data, to: .host))
        }
    }

    // MARK: - Progress

    /// SPEC invariant 3: local confirm produced and a valid confirm from every other party.
    private func passBarrierIfReady(now: UInt64, into effects: inout [Effect]) {
        guard phase == .confirming, localConfirmed, let roster, roomcodeConfirms.count == roster.size else { return }
        phase = .keyExchange
        nextDeadline = after(now, deadlines.figureMs)
        sendShareIfReady(now: now, into: &effects)
    }

    /// SPEC invariant 5: one share per generation, from the frozen figure, never twice.
    private func sendShareIfReady(now: UInt64, into effects: inout [Effect]) {
        guard phase == .keyExchange, let figure = frozenFigure, let roster, let myLetter, let maskKey,
              sentShareGeneration != generation else { return }
        sentShareGeneration = generation
        var pairMasks: [PartyLabel: Int64] = [:]
        for other in roster.others(than: myLetter) {
            let lo = min(myLetter, other.label), hi = max(myLetter, other.label)
            pairMasks[other.label] = maskKey.mask(with: other.maskPublicKey, lo: lo, hi: hi)
        }
        let content = ShareString.format(Wraparound.share(figure: figure, me: myLetter, pairMasks: pairMasks))
        let data = Envelope.signed(action: .share, session: session!, rosterHash: roster.rosterHash,
                                   party: myLetter.letter, content: content, key: signingKey!)
        shares[myLetter] = (content, try! Signature(base64: data.sig))
        if role == .host {
            for peer in rosterPeers.sorted(by: { $0.key < $1.key }).map(\.value) {
                effects.append(.send(data.encoded(), to: peer))
            }
        } else {
            effects.append(.send(data.encoded(), to: .host))
        }
        phase = .sharing
        sumIfComplete(now: now, into: &effects)
    }

    /// SPEC invariant 6: sum only when all N shares are present and verified.
    private func sumIfComplete(now: UInt64, into effects: inout [Effect]) {
        guard phase == .sharing, let roster, let myLetter, shares.count == roster.size else { return }
        let ordered = roster.parties.map { shares[$0.label]!.content }
        sum = Wraparound.sum(ordered.map { try! ShareString.parse($0) })
        let digest = Wire.resultDigest(session: session!, rosterHash: roster.rosterHash, sharesInLetterOrder: ordered)
        myResultDigest = digest
        let data = Envelope.signed(action: .resultConfirm, session: session!, rosterHash: roster.rosterHash,
                                   party: myLetter.letter, content: digest, key: signingKey!)
        resultConfirms[myLetter] = (digest, try! Signature(base64: data.sig))
        if role == .host {
            for peer in rosterPeers.sorted(by: { $0.key < $1.key }).map(\.value) {
                effects.append(.send(data.encoded(), to: peer))
            }
        } else {
            effects.append(.send(data.encoded(), to: .host))
        }
        phase = .collectingConfirmations
        nextDeadline = after(now, deadlines.confirmationsMs)
        resolveIfComplete(now: now)
    }

    private func resolveIfComplete(now: UInt64) {
        guard phase == .collectingConfirmations, let roster, resultConfirms.count == roster.size else { return }
        resolve()
    }

    /// SPEC invariant 7: agreement only when every party signed this phone's exact share set.
    private func resolve() {
        guard let roster, let myResultDigest else { return }
        let mismatched = roster.parties.map(\.label).filter { label in
            if let confirm = resultConfirms[label] { return confirm.content != myResultDigest }
            return false
        }
        let missing = roster.parties.map(\.label).filter { resultConfirms[$0] == nil }
        let outcome: Outcome
        if !mismatched.isEmpty { outcome = .mismatch(mismatched) }
        else if !missing.isEmpty { outcome = .partial(missing: missing) }
        else { outcome = .agreed }
        record = RoundRecord(outcome: outcome, session: session!, rosterHash: roster.rosterHash, label: roster.label, parties: roster.parties,
                             shares: shares.mapValues(\.content), shareSignatures: shares.mapValues(\.signature),
                             resultConfirmSignatures: resultConfirms.mapValues(\.signature),
                             roomcodeConfirmSignatures: roomcodeConfirms.mapValues(\.signature), sum: sum!)
        phase = .complete(outcome)
        endRound()
    }

    /// Round end: figures and mask keys go; the signing key stays so the host can sign a restart.
    private func endRound() {
        nextDeadline = nil
        frozenFigure = nil
        maskKey = nil
    }

    // MARK: - Failure, deadlines, disconnects

    private func fail(_ reason: FailureReason, now: UInt64, into effects: inout [Effect]) {
        guard !phase.isTerminal else { return }
        let wasLocked = phase.isLocked
        phase = .failed(reason)
        sum = nil
        endRound()
        guard role == .host else { return }
        let abortReason: Wire.AbortReason
        switch reason {
        case .timeout: abortReason = .timeout
        case .peerLeft: abortReason = .peerLeft
        case .conflictingMessage: abortReason = .conflict
        case .rosterMismatch, .invalidRoster: abortReason = .rosterMismatch
        case .connectionLost, .aborted, .declined, .hostRestarted: abortReason = .hostLeft
        }
        let targets = wasLocked ? rosterPeers.sorted(by: { $0.key < $1.key }).map(\.value)
                                : (pending + admitted).map(\.peer)
        let data = control(.abort(abortReason))
        for peer in targets where connected.contains(peer) {
            effects.append(.send(data, to: peer))
        }
    }

    private func expire(now: UInt64, into effects: inout [Effect]) {
        switch phase {
        case .lobby: fail(.timeout(.lobby), now: now, into: &effects)
        case .confirming: fail(.timeout(.confirming), now: now, into: &effects)
        case .keyExchange: fail(.timeout(.keyExchange), now: now, into: &effects)
        case .sharing: fail(.timeout(.sharing), now: now, into: &effects)
        case .collectingConfirmations: resolve()
        case .idle, .complete, .failed:
            nextDeadline = nil
            restartOffer = nil
        }
    }

    private func peerDisconnected(_ peer: PeerID, now: UInt64, into effects: inout [Effect]) {
        guard let role else { return }
        if role == .joiner {
            guard peer == .host else { return }
            fail(.connectionLost, now: now, into: &effects)
            return
        }
        guard connected.remove(peer) != nil else { return }
        declinedPeers.remove(peer)
        messageCounts[peer] = nil
        connectionDeadlines[peer] = nil
        carriedPeers.remove(peer)
        pending.removeAll { $0.peer == peer }
        if phase == .lobby {
            admitted.removeAll { $0.peer == peer }
            lockIfRestartReady(now: now, into: &effects)
            return
        }
        guard let letter = rosterPeers.first(where: { $0.value == peer })?.key else { return }
        if phase.isLocked {
            rosterPeers[letter] = nil
            fail(.peerLeft(letter), now: now, into: &effects)
        } else {
            rosterPeers[letter] = nil
        }
    }

    // MARK: - Restart and leave

    /// SPEC invariant 9: the host applies the restart to itself first, then tells everyone.
    private func restart(now: UInt64, into effects: inout [Effect]) {
        guard let roster, phase.isLocked || phase.isTerminal else { effects.append(.rejected(.wrongPhase)); return }
        let remaining = rosterPeers.filter { connected.contains($0.value) }.map(\.value)
        let size = remaining.count + 1
        guard size >= Roster.minimumSize else { effects.append(.rejected(.notEnoughPeople)); return }
        let oldKey = signingKey!
        let oldSession = session!
        previousRound = (roster.size, roster.parties.map(\.nickname).sorted())
        let newSession = SessionID.random()
        beginSession(newSession, nonce: Wire.randomNonce(), now: now)
        maxSize = size
        carriedPeers = Set(remaining)
        restartPending = true
        nextDeadline = after(now, deadlines.confirmingMs)
        for peer in remaining { connectionDeadlines[peer] = after(now, deadlines.confirmingMs) }
        ownHelloSignature = signHello(Wire.Hello(mask: maskKey!.publicKey, nonce: nonce!, nickname: nickname))
        let message = Wire.Control.restart(session: newSession, nonce: nonce!, label: label!, size: size,
                                           host: signingKey!.verifyingKey)
        let data = Envelope.signed(action: .control, session: oldSession, party: Wire.hostParty,
                                   content: Wire.encode(message), key: oldKey).encoded()
        for peer in remaining.sorted(by: { $0.raw < $1.raw }) {
            effects.append(.send(data, to: peer))
        }
    }

    private func acceptRestart(now: UInt64, into effects: inout [Effect]) {
        guard role == .joiner, let offer = restartOffer else { effects.append(.rejected(.wrongPhase)); return }
        if let roster { previousRound = (roster.size, roster.parties.map(\.nickname).sorted()) }
        else if previousRound == nil { previousRound = (0, []) }
        hostKey = offer.host
        label = offer.label
        maxSize = offer.size
        beginSession(offer.session, nonce: offer.nonce, now: now)
        nextDeadline = after(now, deadlines.confirmingMs)
        sendHello(into: &effects)
    }

    private func leave(into effects: inout [Effect]) {
        if role == .host {
            if session != nil, signingKey != nil, !phase.isTerminal {
                let data = control(.abort(.hostLeft))
                for peer in connected.sorted(by: { $0.raw < $1.raw }) { effects.append(.send(data, to: peer)) }
            }
            for peer in connected.sorted(by: { $0.raw < $1.raw }) { effects.append(.disconnect(peer)) }
        } else if role == .joiner {
            effects.append(.disconnect(.host))
        }
        role = nil
        phase = .idle
        session = nil
        nonce = nil
        signingKey = nil
        maskKey = nil
        frozenFigure = nil
        hostKey = nil
        label = nil
        maxSize = 0
        roster = nil
        myLetter = nil
        nextDeadline = nil
        sum = nil
        record = nil
        restartRosterChanged = false
        restartOffer = nil
        localConfirmed = false
        connected = []
        pending = []
        admitted = []
        declinedPeers = []
        connectionDeadlines = [:]
        messageCounts = [:]
        rosterPeers = [:]
        carriedPeers = []
        restartPending = false
        previousRound = nil
        roomcodeConfirms = [:]
        shares = [:]
        resultConfirms = [:]
        sentShareGeneration = nil
        myResultDigest = nil
    }
}
