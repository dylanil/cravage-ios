import XCTest
import Foundation
@testable import CravageCore

/// In-memory star network for RoundEngine tests. Node 0 is the host; nodes 1..n-1 are joiners.
/// The host addresses joiner k as PeerID(k); every joiner addresses the host as PeerID.host.
/// Every message goes through the real route: engine effects -> bytes -> handle(.received).
final class StarBus {
    struct Sent { let from: Int; let to: Int; let data: Data }

    let engines: [RoundEngine]
    var now: UInt64 = 1_000
    var connected: Set<Int> = []
    var inFlight: [(to: Int, from: Int, data: Data)] = []
    var sent: [Sent] = []
    var rejections: [Int: [Rejection]] = [:]
    /// Rewrites one hop. Return [] to drop, several items to duplicate or inject.
    var intercept: ((_ from: Int, _ to: Int, _ data: Data) -> [Data])?

    var host: RoundEngine { engines[0] }
    var size: Int { engines.count }
    var joinerNodes: Range<Int> { 1..<engines.count }

    init(nodes: Int, deadlines: Deadlines = .forTests) {
        engines = (0..<nodes).map { _ in RoundEngine(deadlines: deadlines) }
    }

    @discardableResult
    func deliver(_ node: Int, _ event: Event) -> [Effect] {
        let effects = engines[node].handle(event, now: now)
        apply(effects, from: node)
        return effects
    }

    func apply(_ effects: [Effect], from node: Int) {
        for effect in effects {
            switch effect {
            case let .send(data, to):
                let target = node == 0 ? to.raw : 0
                if node != 0 { XCTAssertEqual(to, .host, "a joiner only ever talks to the host") }
                let link = node == 0 ? target : node
                guard connected.contains(link) else { continue }
                sent.append(Sent(from: node, to: target, data: data))
                for item in intercept?(node, target, data) ?? [data] {
                    inFlight.append((to: target, from: node, data: item))
                }
            case let .disconnect(peer):
                drop(node == 0 ? peer.raw : node)
            case let .rejected(reason):
                rejections[node, default: []].append(reason)
            }
        }
    }

    /// Delivers every in-flight message in FIFO order until the network is quiet.
    func run(limit: Int = 20_000) {
        var steps = 0
        while !inFlight.isEmpty {
            steps += 1
            precondition(steps < limit, "bus did not go quiet")
            let message = inFlight.removeFirst()
            let link = message.to == 0 ? message.from : message.to
            guard connected.contains(link) else { continue }
            let from = message.to == 0 ? PeerID(message.from) : PeerID.host
            deliver(message.to, .received(message.data, from: from))
        }
    }

    /// Closes the link to joiner k, as a transport error would, on both ends.
    func drop(_ k: Int) {
        guard connected.remove(k) != nil else { return }
        inFlight.removeAll { $0.to == k || $0.from == k }
        deliver(0, .peerDisconnected(PeerID(k)))
        if k < size { deliver(k, .peerDisconnected(.host)) }
    }

    func advance(ms: UInt64) {
        now += ms
        for node in 0..<size { deliver(node, .tick) }
        run()
    }

    /// Messages of `action` that `node` put on the wire (forwarded copies excluded).
    func originated(by node: Int, _ action: MessageAction) -> [VerifiedMessage] {
        let key = engines[node].signingKey?.verifyingKey
        return sent.filter { $0.from == node }
            .compactMap { try? Envelope.decodeAndVerify($0.data) }
            .filter { $0.action == action && $0.sender == key }
            .reduce(into: [VerifiedMessage]()) { unique, message in
                if !unique.contains(message) { unique.append(message) }
            }
    }

    func sentAny(_ action: MessageAction) -> Bool {
        sent.contains { (try? Envelope.decodeAndVerify($0.data))?.action == action }
    }

    // MARK: - Scripted steps

    static func lobby(nodes: Int, entitled: Bool = true, deadlines: Deadlines = .forTests) -> StarBus {
        let bus = StarBus(nodes: nodes, deadlines: deadlines)
        bus.deliver(0, .createRoom(label: "Average salary", maxSize: nodes, nickname: "Host", entitled: entitled))
        for k in bus.joinerNodes { bus.join(k) }
        return bus
    }

    func join(_ k: Int, nickname: String? = nil) {
        connected.insert(k)
        deliver(k, .joinRoom(nickname: nickname ?? "Joiner \(k)"))
        deliver(0, .peerConnected(PeerID(k)))
        run()
    }

    func admitAll() {
        for pending in host.pendingJoiners {
            deliver(0, .admit(pending.verifyingKey, generation: host.generation))
        }
        run()
    }

    func start() {
        deliver(0, .start(generation: host.generation))
        run()
    }

    func confirm(_ nodes: [Int]? = nil) {
        for node in nodes ?? Array(0..<size) {
            deliver(node, .confirmRoomCode(generation: engines[node].generation))
        }
        run()
    }

    func submit(_ figures: [Int: Int64]) {
        for (node, figure) in figures.sorted(by: { $0.key < $1.key }) {
            deliver(node, .submitFigure(figure, generation: engines[node].generation))
        }
        run()
    }

    static func locked(nodes: Int, deadlines: Deadlines = .forTests) -> StarBus {
        let bus = lobby(nodes: nodes, entitled: nodes > 3, deadlines: deadlines)
        bus.admitAll()
        bus.start()
        return bus
    }

    static func completed(figures: [Int64], deadlines: Deadlines = .forTests) -> StarBus {
        let bus = locked(nodes: figures.count, deadlines: deadlines)
        bus.confirm()
        bus.submit(Dictionary(uniqueKeysWithValues: figures.enumerated().map { ($0.offset, $0.element) }))
        return bus
    }

    func phases() -> [Phase] { engines.map(\.phase) }

    /// A message signed by `node`'s current round key, bound to its current roster.
    func forged(by node: Int, _ action: MessageAction, content: String, party: String? = nil,
                rosterHash: Data?? = nil) -> Data {
        let engine = engines[node]
        let hash: Data? = rosterHash ?? engine.roster?.rosterHash
        return Envelope.signed(action: action, session: engine.session!, rosterHash: hash,
                               party: party ?? engine.myLetter!.letter, content: content,
                               key: engine.signingKey!).encoded()
    }
}

extension Deadlines {
    static let forTests = Deadlines(lobbyMs: 600_000, confirmingMs: 60_000, figureMs: 90_000, confirmationsMs: 10_000)
}
