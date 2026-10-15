import Foundation
import Network
import CravageCore

// The only file in the app that imports Network. iOS 26 NetworkListener / NetworkBrowser /
// NetworkConnection over peer-to-peer-capable TCP, star topology: the host listens and advertises
// `_cravage._tcp`; each joiner opens one connection to the host. Frames are CravageCore.Framing.
//
// Lessons carried from the 2026-09-13 connectivity spike on three phones and the transport review
// of 2026-09-14:
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

    private(set) var listener: NetworkListener<TCP>?
    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    /// Bumped by every start and stop, so work from an earlier start can recognise itself as stale.
    private var startToken = 0
    private var endpoints: [String: Bonjour.Endpoint] = [:]
    private var nextPeer = 1
    private var links: [PeerID: Link] = [:]
    private var limiter = AcceptLimiter()
    private(set) var sendFailures = 0
    /// Every link opened since the last start or stop, in order, ended ones included.
    private(set) var linkLog = LinkLog()
    private(set) var registrationCounts = RegistrationCounts()
    /// The made-up name the room asked to be registered under; the closed listing is set with it
    /// again. Never empty: an empty name, like nil, registers under the device's name.
    private var serviceName: String?
    private let origin = ContinuousClock.now

    /// One open connection: its receive loop, its outbox, and whoever waits for it to close.
    @MainActor
    final class Link {
        let outbox: Outbox
        var receiveTask: Task<Void, Never>?
        private var closedWaiters: [CheckedContinuation<Void, Never>] = []
        private var closing = false
        // Diagnostics only: counts and times, never content.
        private let toHost: Bool
        private let openedAt = ContinuousClock.now
        private var framesReceived = 0
        private var lastReceivedAt: ContinuousClock.Instant?
        private var route: LinkReport.Route = .unknown
        private var routeChanges = 0
        private var timesUnusable = 0
        private var usable: Bool?
        /// Reads the route the connection is on now; set for a real connection only.
        var currentRoute: (() -> LinkReport.Route)?
        /// Why the link ended. The first cause wins: a failed send that leads to a close is still a
        /// failed send.
        private var cause: LinkReport.End?
        /// Taken once the link has closed, so a later report says how it was then and counts what
        /// the close drained (an abort, a decline).
        private var frozen: LinkReport?

        init(outbox: Outbox, toHost: Bool) {
            self.outbox = outbox
            self.toHost = toHost
        }

        func frameReceived() {
            framesReceived += 1
            lastReceivedAt = .now
            if let currentRoute { routeSeen(currentRoute()) }
        }

        func routeSeen(_ seen: LinkReport.Route) {
            guard seen != .unknown, seen != route else { return }
            if route != .unknown { routeChanges += 1 }
            route = seen
        }

        /// Counts spells, not callbacks: nothing documents how often the handler repeats itself.
        func usableChanged(_ now: Bool) {
            if !now, usable != false { timesUnusable += 1 }
            usable = now
        }

        func ended(_ end: LinkReport.End) {
            if cause == nil { cause = end }
        }

        func report() -> LinkReport {
            if let frozen { return frozen }
            let now = ContinuousClock.now
            return LinkReport(toHost: toHost, end: cause ?? .open,
                              route: route, routeChanges: routeChanges, timesUnusable: timesUnusable,
                              secondsOpen: Self.seconds(now - openedAt),
                              framesSent: outbox.sentCount,
                              framesReceived: framesReceived,
                              waitingToSend: outbox.waitingCount,
                              secondsSending: outbox.sendingSince.map { Self.seconds(now - $0) },
                              secondsSinceLastReceived: lastReceivedAt.map { Self.seconds(now - $0) })
        }

        private static func seconds(_ duration: Duration) -> Int { Int(max(duration.components.seconds, 0)) }

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
            ended(.closedHere)
            frozen = report()
            // The log outlives the link; it must not keep the connection or unsent envelopes alive.
            currentRoute = nil
            outbox.discardQueued()
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
        let txt = Self.openListing(label: label, size: size, hostNickname: hostNickname)
        let name = Self.newServiceName()
        let listener: NetworkListener<TCP>
        do {
            listener = try NetworkListener(for: .bonjour(name: name, type: serviceType, txtRecord: txt),
                                           using: .parameters { TCP() }.peerToPeerIncluded(true))
        } catch {
            onEvent?(.hostingFailed(Self.problem(from: error)))
            return
        }
        self.listener = listener
        serviceName = name
        limiter = AcceptLimiter()
        refreshConnectionBudget()
        listener.onStateUpdate { [weak self] _, state in
            Task { @MainActor in
                guard let self, self.startToken == token, let problem = Self.fatalProblem(state) else { return }
                self.onEvent?(.hostingFailed(problem))
            }
        }
        listener.onServiceRegistrationUpdate { [weak self] _, change in
            Task { @MainActor in
                guard let self, self.startToken == token else { return }
                self.registrationCounts.record(change)
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

    /// The documentation: NWListener.Service's TXT record, "Update the txtRecord by setting the
    /// service on the listener with the same name/type/domain and a new TXT record object";
    /// NetworkListener.service, "May be modified after the listener becomes ready to update the TXT
    /// record or change the advertised service"; `.bonjour(name:type:domain:txtRecord:)`, "Later, a
    /// text record can be advertised by setting `service` on `NetworkListener`". None of them says
    /// whether "the same name" is the one asked for or one the system changed for a clash, what
    /// setting it before the listener is ready does (the unit test does that; the app closes the
    /// listing at the lock or the end of the lobby), that the registration survives, how soon
    /// browsers see it, or anything of open connections or peer-to-peer Wi-Fi. Loopback probes on
    /// the Mac (2026-10-13, 2026-10-14) saw the service set again with the name asked for update the
    /// record in place, with no removal of the registration, an instance renamed for a clash keep
    /// its new name, an open connection carry on, and a running browser deliver the new record
    /// within a second, sometimes after a delivery with an empty one, which the list treats as no
    /// room. A nil or empty name after a made-up one removed the registration and added it again
    /// under the Mac's own name. Device runs (2026-10-14) kept the registration through the round,
    /// asking for no name, on a home network and with every link over peer-to-peer Wi-Fi (the
    /// report counting one added and none removed), and with the made-up name on a home network.
    func closeListing() {
        guard let serviceName else { return }
        listener?.service = Self.closedService(name: serviceName)
    }

    static func closedService(name: String) -> NWListener.Service {
        NWListener.Service(name: name, type: serviceType, txtRecord: closedListing)
    }

    /// Decision 2026-10-14: given no name, the system registers the room under the phone's own name
    /// (Settings, General, About), which any Bonjour browser on the network can read, though the
    /// app never shows it. NWListener.Service.name: "if nil the system name will be used";
    /// advertise_descriptor.h: "If the name is unspecified, the default name for the device will be
    /// used". A device run saw it. The room asks instead for "Cravage" and four characters drawn
    /// afresh for each room, so the name says nothing about the phone and does not follow it from
    /// room to room. On that run the record led to a host name iOS made up, not the phone's name.
    static func newServiceName() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return "Cravage " + String((0..<4).map { _ in characters[Int.random(in: 0..<characters.count)] })
    }

    /// What a room taking people lists: its name and size, the host's name and the version.
    static func openListing(label: String, size: Int, hostNickname: String) -> NWTXTRecord {
        NWTXTRecord(["v": String(CravageCore.protocolVersion), "label": label, "size": String(size), "host": hostNickname])
    }

    /// Decision 2026-10-13: what a room taking nobody new lists. It names nothing, so a build from
    /// before the "closed" key leaves it off its list as well, for want of a room name.
    static var closedListing: NWTXTRecord {
        NWTXTRecord(["v": String(CravageCore.protocolVersion), "closed": "1"])
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
        onEvent?(Self.roomList(found.map { (id: $0.id, txt: $0.txtRecord) }))
    }

    /// Every listing counts as found, a closed or malformed one included; only open rooms go on
    /// the list.
    static func roomList(_ listings: [(id: String, txt: NWTXTRecord)]) -> TransportEvent {
        let rooms = listings.compactMap { advert(id: $0.id, txt: $0.txt) }
        return .roomsChanged(rooms, listings: listings.count)
    }

    /// A room for the nearby list, or nil for a closed or malformed listing.
    static func advert(id: String, txt: NWTXTRecord) -> RoomAdvert? {
        guard txt.getEntry(for: "closed") == nil,
              let label = txt["label"], RoomText.isValidLabel(label),
              let host = txt["host"], RoomText.isValidNickname(host),
              let size = txt["size"].flatMap(Int.init), (Roster.minimumSize...Roster.maximumSize).contains(size),
              let version = txt["v"].flatMap(Int.init) else { return nil }
        return RoomAdvert(id: id, label: label, size: size, hostNickname: host, protocolVersion: version)
    }

    func connect(to roomID: String) {
        let token = startToken
        if let old = links.removeValue(forKey: .host) {
            old.ended(.closedHere)
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
        let link = open(as: peer, send: { data in
            try await connection.send(data)
        }, receiveExactly: { count in
            try await connection.receive(exactly: count).content
        })
        // connection.h documents the C calls: nw_connection_copy_current_path "will reflect the
        // connected path" once established, and the viability handler says "whether or not read and
        // write calls will succeed on a ready connection". That `currentPath`, `onPathUpdate` and
        // `onViabilityUpdate` behave the same is inferred; they have no doc comments. The route is
        // also read on every frame, in case a handler set on a connection the listener has already
        // started misses its first path. The handlers are formed here, on the main actor, and run
        // there (`@_inheritActorContext`), so they update the link in order with the frames.
        link.currentRoute = { [weak connection] in connection?.currentPath.map(Self.route(of:)) ?? .unknown }
        connection.onPathUpdate { [weak link] _, path in
            link?.routeSeen(Self.route(of: path))
        }
        connection.onViabilityUpdate { [weak link] _, viable in
            link?.usableChanged(viable)
        }
        return link
    }

    nonisolated static func route(of path: NWPath) -> LinkReport.Route {
        route(interfaces: path.availableInterfaces.map { ($0.type, $0.name) })
    }

    /// path.h lists "all interfaces associated with the path" and says nothing of their order or of
    /// which one carries the connection, so a path over more than one kind says so.
    nonisolated static func route(interfaces: [(NWInterface.InterfaceType, String)]) -> LinkReport.Route {
        let routes = Set(interfaces.map { route(type: $0.0, name: $0.1) })
        guard let only = routes.first else { return .unknown }
        return routes.count == 1 ? only : .mixed
    }

    /// The interface name is read only to tell Apple's peer-to-peer Wi-Fi from a Wi-Fi network,
    /// which the interface type does not: `awdl` (Apple Wireless Direct Link) and `llw` (low
    /// latency WLAN) are the names it has been seen under, not documented ones. Only the fixed word
    /// leaves this function.
    nonisolated static func route(type: NWInterface.InterfaceType, name: String) -> LinkReport.Route {
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return .peerToPeer }
        switch type {
        case .wifi: return .wifiNetwork
        case .wiredEthernet: return .wired
        case .cellular: return .cellular
        case .loopback: return .loopback
        case .other: return .other
        @unknown default: return .other
        }
    }

    /// TCP byte IO is supplied at this boundary; framing and connection lifetime stay here.
    @discardableResult
    func open(as peer: PeerID, send: @escaping @Sendable (Data) async throws -> Void,
              receiveExactly: @escaping @Sendable (Int) async throws -> Data) -> Link {
        let token = startToken
        let outbox = Outbox(send: { data in
            try await send(try Framing.encode(data))
        })
        let link = Link(outbox: outbox, toHost: peer == .host)
        links[peer] = link
        linkLog.add { link.report() }
        // A failed send ends the connection now, reported like any other close, instead of leaving a
        // link that looks open while what was queued for it is gone.
        outbox.onFailure = { [weak self, weak link] in
            link?.ended(.sendFailed)
            guard let self else { return }
            self.sendFailures += 1
            guard let link, self.links[peer] === link else { return }
            self.disconnect(peer)
        }
        link.receiveTask = Task { [weak self] in
            let end = await Framing.pump(receiveExactly: receiveExactly, deliver: { [weak self] data in
                await self?.delivered(data, from: peer, on: link)
            })
            switch end {
            case .failed: link.ended(.lost)
            case .closed: link.ended(.closedThere)
            case .rejected: link.ended(.badFrame)
            case .cancelled: link.ended(.closedHere)
            }
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

    /// A link that has left the table still reads until its close finishes; what arrives then is
    /// counted, so both phones' counts agree, but never handed to the engine.
    private func delivered(_ data: Data, from peer: PeerID, on link: Link) {
        link.frameReceived()
        guard links[peer] === link else { return }
        onEvent?(.received(data, from: peer))
    }

    func send(_ data: Data, to peer: PeerID) {
        guard let link = links[peer] else { return }
        if !link.outbox.enqueue(data) {
            // Full or failed: the peer is not reading. Drop the connection rather than lose envelopes quietly.
            // A failed send has already recorded itself; otherwise the queue was full.
            link.ended(.queueFull)
            disconnect(peer)
        }
    }

    func disconnect(_ peer: PeerID) {
        guard let link = links.removeValue(forKey: peer) else { return }
        link.ended(.closedHere)
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
        linkLog = LinkLog()
        registrationCounts = RegistrationCounts()
        endpoints = [:]
        for link in closing {
            link.ended(.leftRoom)
            Task { await link.close(drain: true) }
        }
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

extension RegistrationCounts {
    mutating func record(_ change: NetworkListener<TCP>.ServiceRegistrationChange) {
        switch change {
        case .add: added += 1
        case .remove: removed += 1
        @unknown default: break
        }
    }
}
