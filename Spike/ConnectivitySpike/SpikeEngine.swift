import Foundation
import Network
import Observation

// Delivery step 2 spike: prove three phones can find each other, connect through a host,
// get admitted, and pass messages, using the iOS 26 NetworkListener/NetworkBrowser/NetworkConnection
// interface (not Multipeer Connectivity - deprecated per TN3213). No crypto, no real protocol here;
// that lives in CravageCore once the design is settled. This whole target is thrown away afterward.

private let serviceType = "_cravagespike._tcp"

private typealias SpikeProtocol = Network.Coder<SpikeMessage, SpikeMessage, Network.NetworkJSONCoder>

private func spikeStack() -> SpikeProtocol {
    Coder(SpikeMessage.self, using: NetworkJSONCoder()) { TCP() }
}

@MainActor
@Observable
final class SpikeEngine {
    var role: SpikeRole?
    var nickname: String = "Phone-\(Int.random(in: 1000...9999))"
    let myID = UUID().uuidString

    var log: [LogEntry] = []

    // Host-side state
    var pendingRequests: [Peer] = []
    var admittedPeers: [Peer] = []
    private var listener: NetworkListener<SpikeProtocol>?
    private var hostConnections: [String: NetworkConnection<SpikeProtocol>] = [:]

    // Join-side state
    var discoveredHosts: [Bonjour.Endpoint] = []
    var connectedAndAdmitted = false
    var declined = false
    private var browser: NetworkBrowser<Bonjour>?
    private var hostConnection: NetworkConnection<SpikeProtocol>?

    func addLog(_ text: String) {
        log.append(LogEntry(time: Date(), text: text))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    // MARK: - Host role

    func startHosting(label: String) {
        role = .host
        addLog("Starting to host room '\(label)' as \(nickname)...")
        let txt = NWTXTRecord(["label": label, "host": nickname])
        do {
            let listener = try NetworkListener(for: .bonjour(name: nil, type: serviceType, txtRecord: txt)) {
                spikeStack()
            }
            self.listener = listener
            listener.onStateUpdate { [weak self] _, state in
                Task { @MainActor in self?.addLog("Listener state: \(state)") }
            }
            Task {
                do {
                    try await listener.run { [weak self] connection in
                        guard let self else { return }
                        await self.handleIncoming(connection: connection)
                    }
                } catch {
                    await MainActor.run { self.addLog("Listener stopped: \(error)") }
                }
            }
        } catch {
            addLog("Failed to start hosting: \(error)")
        }
    }

    private func handleIncoming(connection: NetworkConnection<SpikeProtocol>) async {
        addLog("Incoming connection from a nearby phone...")
        connection.onStateUpdate { [weak self] _, state in
            Task { @MainActor in self?.addLog("Peer connection state: \(state)") }
        }
        do {
            let first = try await connection.receive()
            let hello = first.content
            guard hello.kind == .hello else {
                addLog("First message wasn't a hello, dropping connection.")
                return
            }
            let peerID = hello.senderID
            hostConnections[peerID] = connection
            pendingRequests.append(Peer(id: peerID, nickname: hello.senderNickname, admitted: false))
            addLog("\(hello.senderNickname) wants to join.")

            for try await message in connection.messages {
                let msg = message.content
                switch msg.kind {
                case .chat:
                    addLog("\(msg.senderNickname): \(msg.text)")
                    await relay(msg, from: peerID)
                default:
                    break
                }
            }
            addLog("\(hello.senderNickname) disconnected.")
            pendingRequests.removeAll { $0.id == peerID }
            admittedPeers.removeAll { $0.id == peerID }
            hostConnections[peerID] = nil
        } catch {
            addLog("Connection from a peer failed: \(error)")
        }
    }

    func admit(_ peer: Peer) {
        guard let connection = hostConnections[peer.id] else { return }
        pendingRequests.removeAll { $0.id == peer.id }
        admittedPeers.append(Peer(id: peer.id, nickname: peer.nickname, admitted: true))
        Task {
            do {
                try await connection.send(SpikeMessage(kind: .admit, senderID: myID, senderNickname: nickname, text: ""))
                addLog("Admitted \(peer.nickname).")
            } catch {
                addLog("Failed to notify \(peer.nickname) of admission: \(error)")
            }
        }
    }

    func decline(_ peer: Peer) {
        guard let connection = hostConnections[peer.id] else { return }
        pendingRequests.removeAll { $0.id == peer.id }
        Task {
            try? await connection.send(SpikeMessage(kind: .decline, senderID: myID, senderNickname: nickname, text: ""))
            addLog("Declined \(peer.nickname).")
            hostConnections[peer.id] = nil
        }
    }

    private func relay(_ message: SpikeMessage, from senderID: String) async {
        for (peerID, connection) in hostConnections where peerID != senderID {
            guard admittedPeers.contains(where: { $0.id == peerID }) else { continue }
            do {
                try await connection.send(message)
            } catch {
                addLog("Failed to relay to \(peerID): \(error)")
            }
        }
    }

    func hostBroadcast(text: String) {
        guard !text.isEmpty else { return }
        let msg = SpikeMessage(kind: .chat, senderID: myID, senderNickname: nickname, text: text)
        addLog("Me (\(nickname)): \(text)")
        Task { await relay(msg, from: myID) }
    }

    // MARK: - Join role

    func startBrowsing() {
        role = .join
        addLog("Looking for rooms nearby...")
        let browser = NetworkBrowser(for: Network.Bonjour.bonjour(serviceType, includeTxtRecord: true))
        self.browser = browser
        browser.onStateUpdate { [weak self] _, state in
            Task { @MainActor in self?.addLog("Browser state: \(state)") }
        }
        Task {
            do {
                try await browser.run { [weak self] endpoints in
                    await MainActor.run { self?.discoveredHosts = endpoints }
                }
            } catch {
                await MainActor.run { self.addLog("Browsing stopped: \(error)") }
            }
        }
    }

    func requestJoin(_ endpoint: Bonjour.Endpoint) {
        addLog("Connecting to \(endpoint.name)...")
        let connection = NetworkConnection(to: endpoint) { spikeStack() }
        self.hostConnection = connection
        connection.onStateUpdate { [weak self] _, state in
            Task { @MainActor in self?.addLog("Connection state: \(state)") }
        }
        Task {
            do {
                try await connection.send(SpikeMessage(kind: .hello, senderID: myID, senderNickname: nickname, text: ""))
                for try await message in connection.messages {
                    let msg = message.content
                    switch msg.kind {
                    case .admit:
                        connectedAndAdmitted = true
                        addLog("You're in the room.")
                    case .decline:
                        declined = true
                        addLog("The host declined your request to join.")
                    case .chat:
                        addLog("\(msg.senderNickname): \(msg.text)")
                    default:
                        break
                    }
                }
                addLog("Disconnected from host.")
                connectedAndAdmitted = false
            } catch {
                addLog("Connection error: \(error)")
            }
        }
    }

    func sendChat(text: String) {
        guard !text.isEmpty, let connection = hostConnection else { return }
        let msg = SpikeMessage(kind: .chat, senderID: myID, senderNickname: nickname, text: text)
        addLog("Me (\(nickname)): \(text)")
        Task {
            do { try await connection.send(msg) } catch { addLog("Send failed: \(error)") }
        }
    }
}
