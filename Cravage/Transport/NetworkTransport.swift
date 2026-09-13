import Foundation
import Network
import CravageCore

// The only file in the app that imports Network. iOS 26 NetworkListener / NetworkBrowser /
// NetworkConnection over peer-to-peer-capable TCP, star topology: the host listens and advertises
// `_cravage._tcp`; each joiner opens one connection to the host. Frames are CravageCore.Framing.
//
// Lessons carried from the connectivity spike (docs/review/2026-09-13-connectivity-spike-findings.md):
// cleanup runs after the receive loop returns on every path, never inside the throwing block; a
// connection's bookkeeping is removed only if it is still the one on record; sends to one connection
// are serialised so envelopes cannot reorder.

private let serviceType = "_cravage._tcp"

@MainActor
final class NetworkTransport: RoundTransport {
    var onEvent: ((TransportEvent) -> Void)?

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var endpoints: [String: Bonjour.Endpoint] = [:]
    private var nextPeer = 1
    private var links: [PeerID: Link] = [:]

    /// One open connection: its receive loop and its ordered outbox.
    private final class Link {
        let connection: NetworkConnection<TCP>
        let outbox: AsyncStream<Data>.Continuation
        var tasks: [Task<Void, Never>] = []
        init(connection: NetworkConnection<TCP>, outbox: AsyncStream<Data>.Continuation) {
            self.connection = connection
            self.outbox = outbox
        }
        func close() {
            outbox.finish()
            tasks.forEach { $0.cancel() }
        }
    }

    // MARK: - Host

    func startHosting(label: String, size: Int, hostNickname: String) {
        stopAll()
        let txt = NWTXTRecord(["v": String(CravageCore.protocolVersion), "label": label, "size": String(size), "host": hostNickname])
        let listener: NetworkListener<TCP>
        do {
            listener = try NetworkListener(for: .bonjour(name: nil, type: serviceType, txtRecord: txt),
                                           using: .parameters { TCP() }.peerToPeerIncluded(true))
        } catch {
            onEvent?(.hostingFailed(Self.problem(from: error)))
            return
        }
        listener.newConnectionLimit = RoundEngine.maxConnections
        listener.onStateUpdate { [weak self] _, state in
            Task { @MainActor in
                switch state {
                case let .failed(error), let .waiting(error):
                    self?.onEvent?(.hostingFailed(Self.problem(from: error)))
                default:
                    break
                }
            }
        }
        listenerTask = Task { [weak self] in
            do {
                try await listener.run { connection in
                    await self?.hostAccepted(connection)
                }
            } catch {
                self?.onEvent?(.hostingFailed(Self.problem(from: error)))
            }
        }
    }

    /// Runs for the life of one inbound connection; returning ends it.
    private func hostAccepted(_ connection: NetworkConnection<TCP>) async {
        let peer = PeerID(nextPeer)
        nextPeer += 1
        let link = open(connection, as: peer)
        onEvent?(.peerConnected(peer))
        await link.tasks.first?.value
    }

    // MARK: - Joiner

    func startBrowsing() {
        browserTask?.cancel()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NetworkBrowser(for: .bonjour(serviceType, includeTxtRecord: true), using: parameters)
        browser.onStateUpdate { [weak self] _, state in
            Task { @MainActor in
                switch state {
                case let .failed(error), let .waiting(error):
                    self?.onEvent?(.discoveryFailed(Self.problem(from: error)))
                default:
                    break
                }
            }
        }
        browserTask = Task { [weak self] in
            do {
                try await browser.run { found in
                    self?.roomsFound(found)
                }
            } catch {
                self?.onEvent?(.discoveryFailed(Self.problem(from: error)))
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
        links[.host]?.close()
        links[.host] = nil
        guard let endpoint = endpoints[roomID] else {
            onEvent?(.peerDisconnected(.host))
            return
        }
        let connection = NetworkConnection(to: endpoint, using: .parameters { TCP() }.peerToPeerIncluded(true))
        _ = open(connection, as: .host)
    }

    // MARK: - Shared

    private func open(_ connection: NetworkConnection<TCP>, as peer: PeerID) -> Link {
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let link = Link(connection: connection, outbox: continuation)
        links[peer] = link
        let receive = Task { [weak self] in
            _ = await Framing.pump(receiveExactly: { count in
                try await connection.receive(exactly: count).content
            }, deliver: { [weak self] data in
                await self?.delivered(data, from: peer)
            })
            // Cleanup after the loop, whatever ended it; only if this link is still the one on record.
            guard let self, self.links[peer] === link else { return }
            self.links[peer] = nil
            link.close()
            self.onEvent?(.peerDisconnected(peer))
        }
        let send = Task {
            for await data in stream {
                do { try await connection.send(Framing.encode(data)) } catch { break }
            }
        }
        link.tasks = [receive, send]
        return link
    }

    private func delivered(_ data: Data, from peer: PeerID) {
        guard links[peer] != nil else { return }
        onEvent?(.received(data, from: peer))
    }

    func send(_ data: Data, to peer: PeerID) {
        links[peer]?.outbox.yield(data)
    }

    func disconnect(_ peer: PeerID) {
        guard let link = links.removeValue(forKey: peer) else { return }
        link.close()
        // Reported on the next main-actor turn: the caller is still carrying out engine effects.
        Task { [weak self] in self?.onEvent?(.peerDisconnected(peer)) }
    }

    func stopAll() {
        listenerTask?.cancel()
        listenerTask = nil
        browserTask?.cancel()
        browserTask = nil
        for link in links.values { link.close() }
        links = [:]
        endpoints = [:]
    }

    private static func problem(from error: Error) -> TransportProblem {
        if let error = error as? NWError, case let .dns(code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
            return .localNetworkDenied
        }
        return .unavailable
    }
}
