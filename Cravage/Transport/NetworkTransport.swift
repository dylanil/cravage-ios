import Foundation
import Network
import CravageCore

// The only file in the app that imports Network. iOS 26 NetworkListener / NetworkBrowser /
// NetworkConnection over peer-to-peer-capable TCP, star topology: the host listens and advertises
// `_cravage._tcp`; each joiner opens one connection to the host. Frames are CravageCore.Framing.
//
// Lessons carried from the connectivity spike (docs/review/2026-09-13-connectivity-spike-findings.md)
// and the transport review of 9b6f3f2:
// - cleanup runs after the receive loop returns on every path, and only for the link still on record;
// - sends to one connection are ordered and bounded (Outbox); closing drains what is queued first;
// - the listener's newConnectionLimit is a lifetime budget that Network decrements on every accept,
//   so it is recomputed from the open connections after each accept and each close;
// - inbound accepts are rate limited (SPEC section 2);
// - a cancelled listener or browser from an earlier start never reports a failure.

private let serviceType = "_cravage._tcp"
private let drainMs: UInt64 = 1_500

@MainActor
final class NetworkTransport: RoundTransport {
    var onEvent: ((TransportEvent) -> Void)?

    private var listener: NetworkListener<TCP>?
    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    /// Bumped by every start and stop, so work from an earlier start can recognise itself as stale.
    private var startToken = 0
    private var endpoints: [String: Bonjour.Endpoint] = [:]
    private var nextPeer = 1
    private var links: [PeerID: Link] = [:]
    private var limiter = AcceptLimiter()
    private let origin = ContinuousClock.now

    /// One open connection: its receive loop, its outbox, and whoever waits for it to close.
    @MainActor
    final class Link {
        let outbox: Outbox
        var receiveTask: Task<Void, Never>?
        private var closedWaiters: [CheckedContinuation<Void, Never>] = []
        private var closing = false

        init(outbox: Outbox) { self.outbox = outbox }

        func waitUntilClosed() async {
            if closing && closedWaiters.isEmpty && receiveTask == nil { return }
            await withCheckedContinuation { closedWaiters.append($0) }
        }

        /// Drain the outbox (bounded), then stop receiving and release anyone waiting.
        func close(drain: Bool) async {
            guard !closing else { return }
            closing = true
            await outbox.close(drainMs: drain ? drainMs : 0)
            receiveTask?.cancel()
            receiveTask = nil
            let waiters = closedWaiters
            closedWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    private func nowMs() -> UInt64 {
        let (seconds, attoseconds) = (ContinuousClock.now - origin).components
        return UInt64(max(seconds, 0)) * 1_000 + UInt64(max(attoseconds, 0) / 1_000_000_000_000_000)
    }

    // MARK: - Host

    func startHosting(label: String, size: Int, hostNickname: String) {
        stopAll()
        let token = startToken
        let txt = NWTXTRecord(["v": String(CravageCore.protocolVersion), "label": label, "size": String(size), "host": hostNickname])
        let listener: NetworkListener<TCP>
        do {
            listener = try NetworkListener(for: .bonjour(name: nil, type: serviceType, txtRecord: txt),
                                           using: .parameters { TCP() }.peerToPeerIncluded(true))
        } catch {
            onEvent?(.hostingFailed(Self.problem(from: error)))
            return
        }
        self.listener = listener
        limiter = AcceptLimiter()
        refreshConnectionBudget()
        listener.onStateUpdate { [weak self] _, state in
            Task { @MainActor in
                guard let self, self.startToken == token, let problem = Self.fatalProblem(state) else { return }
                self.onEvent?(.hostingFailed(problem))
            }
        }
        listenerTask = Task { [weak self] in
            do {
                try await listener.run { connection in
                    await self?.hostAccepted(connection, token: token)
                }
            } catch {
                guard let self, self.startToken == token, !(error is CancellationError), !Task.isCancelled else { return }
                self.onEvent?(.hostingFailed(Self.problem(from: error)))
            }
        }
    }

    /// Runs for the life of one inbound connection; returning lets Network close it.
    private func hostAccepted(_ connection: NetworkConnection<TCP>, token: Int) async {
        defer { refreshConnectionBudget() }
        guard startToken == token, limiter.allow(nowMs: nowMs()) else { return }
        let peer = PeerID(nextPeer)
        nextPeer += 1
        let link = open(connection, as: peer)
        onEvent?(.peerConnected(peer))
        await link.waitUntilClosed()
    }

    /// Network decrements newConnectionLimit on every accept and stops accepting at zero, so the
    /// budget is reset from the number of connections actually open.
    private func refreshConnectionBudget() {
        let open = links.keys.filter { $0 != .host }.count
        listener?.newConnectionLimit = max(0, RoundEngine.maxConnections - open)
    }

    // MARK: - Joiner

    func startBrowsing() {
        browserTask?.cancel()
        startToken += 1
        let token = startToken
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NetworkBrowser(for: .bonjour(serviceType, includeTxtRecord: true), using: parameters)
        browser.onStateUpdate { [weak self] _, state in
            Task { @MainActor in
                guard let self, self.startToken == token else { return }
                switch state {
                case let .failed(error):
                    self.onEvent?(.discoveryFailed(Self.problem(from: error)))
                case let .waiting(error) where Self.problem(from: error) == .localNetworkDenied:
                    self.onEvent?(.discoveryFailed(.localNetworkDenied))
                default:
                    break
                }
            }
        }
        browserTask = Task { [weak self] in
            do {
                try await browser.run { found in
                    guard let self, self.startToken == token else { return }
                    self.roomsFound(found)
                }
            } catch {
                guard let self, self.startToken == token, !(error is CancellationError), !Task.isCancelled else { return }
                self.onEvent?(.discoveryFailed(Self.problem(from: error)))
            }
        }
    }

    private func roomsFound(_ found: [Bonjour.Endpoint]) {
        endpoints = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let adverts = found.compactMap { endpoint -> RoomAdvert? in
            let txt = endpoint.txtRecord
            guard let label = txt["label"], RoomText.isValidLabel(label),
                  let host = txt["host"], RoomText.isValidNickname(host),
                  let size = txt["size"].flatMap(Int.init), (Roster.minimumSize...Roster.maximumSize).contains(size),
                  let version = txt["v"].flatMap(Int.init) else { return nil }
            return RoomAdvert(id: endpoint.id, label: label, size: size, hostNickname: host, protocolVersion: version)
        }
        onEvent?(.roomsChanged(adverts))
    }

    func connect(to roomID: String) {
        let token = startToken
        if let old = links.removeValue(forKey: .host) {
            Task { await old.close(drain: false) }
        }
        guard let endpoint = endpoints[roomID] else {
            Task { [weak self] in
                guard let self, self.startToken == token, self.links[.host] == nil else { return }
                self.onEvent?(.peerDisconnected(.host))
            }
            return
        }
        let connection = NetworkConnection(to: endpoint, using: .parameters { TCP() }.peerToPeerIncluded(true))
        _ = open(connection, as: .host)
    }

    // MARK: - Shared

    private func open(_ connection: NetworkConnection<TCP>, as peer: PeerID) -> Link {
        open(as: peer, send: { data in
            try await connection.send(data)
        }, receiveExactly: { count in
            try await connection.receive(exactly: count).content
        })
    }

    /// TCP byte IO is supplied at this boundary; framing and connection lifetime stay here.
    @discardableResult
    func open(as peer: PeerID, send: @escaping @Sendable (Data) async throws -> Void,
              receiveExactly: @escaping @Sendable (Int) async throws -> Data) -> Link {
        let token = startToken
        let outbox = Outbox(send: { data in
            try await send(try Framing.encode(data))
        })
        let link = Link(outbox: outbox)
        links[peer] = link
        link.receiveTask = Task { [weak self] in
            _ = await Framing.pump(receiveExactly: receiveExactly, deliver: { [weak self] data in
                await self?.delivered(data, from: peer, on: link)
            })
            // Cleanup after the loop, whatever ended it; only if this link is still the one on record.
            guard let self, self.links[peer] === link else {
                await link.close(drain: false)
                return
            }
            self.links[peer] = nil
            await link.close(drain: false)
            guard self.startToken == token, self.links[peer] == nil else { return }
            self.refreshConnectionBudget()
            self.onEvent?(.peerDisconnected(peer))
        }
        return link
    }

    private func delivered(_ data: Data, from peer: PeerID, on link: Link) {
        guard links[peer] === link else { return }
        onEvent?(.received(data, from: peer))
    }

    func send(_ data: Data, to peer: PeerID) {
        guard let link = links[peer] else { return }
        if !link.outbox.enqueue(data) {
            // Full or failed: the peer is not reading. Drop the connection rather than lose envelopes quietly.
            disconnect(peer)
        }
    }

    func disconnect(_ peer: PeerID) {
        guard let link = links.removeValue(forKey: peer) else { return }
        let token = startToken
        Task { [weak self] in
            await link.close(drain: true)
            guard let self, self.startToken == token, self.links[peer] == nil else { return }
            self.refreshConnectionBudget()
            self.onEvent?(.peerDisconnected(peer))
        }
    }

    func stopAll() {
        startToken += 1
        listenerTask?.cancel()
        listenerTask = nil
        listener = nil
        browserTask?.cancel()
        browserTask = nil
        let closing = Array(links.values)
        links = [:]
        endpoints = [:]
        for link in closing { Task { await link.close(drain: true) } }
    }

    private static func fatalProblem(_ state: NetworkListener<TCP>.State) -> TransportProblem? {
        switch state {
        case let .failed(error):
            return problem(from: error)
        case let .waiting(error):
            return problem(from: error) == .localNetworkDenied ? .localNetworkDenied : nil
        default:
            return nil
        }
    }

    private static func problem(from error: Error) -> TransportProblem {
        if let error = error as? NWError, case let .dns(code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
            return .localNetworkDenied
        }
        return .unavailable
    }
}
