import Foundation
import CravageCore

/// A room as nearby phones see it before joining: the Bonjour TXT record, untrusted until the
/// room code is compared. `id` is the transport's opaque handle for connecting.
struct RoomAdvert: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let size: Int
    let hostNickname: String
    let protocolVersion: Int
}

enum TransportProblem: Equatable, Sendable {
    /// Local Network access is off for Cravage (TN3179 policy-denied signals).
    case localNetworkDenied
    /// Anything else; the UI shows an honest generic connection error with retry.
    case unavailable
}

enum TransportEvent: Sendable {
    case roomsChanged([RoomAdvert])
    case discoveryFailed(TransportProblem)
    case hostingFailed(TransportProblem)
    /// Host: a new inbound connection.
    case peerConnected(PeerID)
    case received(Data, from: PeerID)
    /// Host: a joiner's connection ended. Joiner: `PeerID.host` ended or failed to open.
    case peerDisconnected(PeerID)
}

/// Moves envelope bytes between phones. No crypto and no protocol decisions: those are the
/// engine's. Implementations deliver `onEvent` on the main actor, in order.
@MainActor
protocol RoundTransport: AnyObject {
    var onEvent: ((TransportEvent) -> Void)? { get set }
    func startHosting(label: String, size: Int, hostNickname: String)
    /// Host: take the room off the nearby list while keeping the listener and every open
    /// connection. Called once the round starts, so a latecomer is not shown a room that can only
    /// turn them away.
    func stopAdvertising()
    func startBrowsing()
    /// Stop looking for rooms while keeping any open connection. Called once a round has started,
    /// so a phone in a round is not still multicasting for `_cravage._tcp`.
    func stopBrowsing()
    /// Joiner: open the single connection to a room's host.
    func connect(to roomID: String)
    func send(_ data: Data, to peer: PeerID)
    func disconnect(_ peer: PeerID)
    /// Stop listening, browsing and every connection.
    func stopAll()
}
