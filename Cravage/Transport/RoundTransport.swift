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

    /// Whether this phone speaks the room's protocol. Every message to or from a room on another
    /// version is refused, so such a room is shown but never joined.
    var isCompatible: Bool { protocolVersion == CravageCore.protocolVersion }
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
    /// Sends that failed since launch. A count only, for the diagnostics report.
    var sendFailures: Int { get }
    /// Every connection opened since the last `startHosting` or `stopAll`, oldest first, ended ones
    /// included. For the diagnostics report, which reads it before `stopAll` clears it.
    var linkReports: [LinkReport] { get }
}

/// What one connection did, in counts and seconds only: no peer name, address or content, so it
/// can go into a diagnostics report. Device report 2026-10-09: one phone's link to the host went
/// silent in both directions mid-round with no failed send; these figures tell a send that never
/// finished from a host that stopped reading from a link that went quiet.
struct LinkReport: Equatable, Sendable {
    enum End: Equatable, Sendable {
        /// Still open when the report was taken.
        case open
        /// The other side closed it, or it failed or reset (`Framing.ConnectionEnd.failed`).
        case lost
        /// The other side broke the framing rules.
        case badFrame
        /// A send threw.
        case sendFailed
        /// This phone closed it: a disconnect, a replacement or a leave.
        case closedHere
    }

    /// True for a joiner's one connection to the host; false for a host's connection to a joiner.
    var toHost: Bool
    var end: End = .open
    /// How long the connection had been open when it ended, or when the report was taken.
    var secondsOpen = 0
    var framesSent = 0
    var framesReceived = 0
    /// Frames handed to the connection and not yet confirmed sent, the one being sent included.
    var waitingToSend = 0
    /// How long the send in progress has been running, when one is.
    var secondsSending: Int?
    /// Seconds since the last frame arrived, measured at the same point as `secondsOpen`. Nil when
    /// nothing ever arrived.
    var secondsSinceLastReceived: Int?
}
