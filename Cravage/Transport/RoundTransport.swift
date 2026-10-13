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
    /// Host: register the room and take connections. Decision 2026-10-13: the registration then
    /// stays until `stopAll` (see `RoundCoordinator.leave`); nothing removes it on its own.
    func startHosting(label: String, size: Int, hostNickname: String)
    /// Host: keep the registration, the listener and every open connection, but say the room takes
    /// nobody new, without its name or the host's, so nearby phones leave it off their lists.
    func closeListing()
    /// Look for rooms until `stopAll`, which since 2026-10-13 is the only thing that ends it.
    func startBrowsing()
    /// Joiner: open the single connection to a room's host.
    func connect(to roomID: String)
    func send(_ data: Data, to peer: PeerID)
    func disconnect(_ peer: PeerID)
    /// Stop listening, browsing and every connection.
    func stopAll()
    /// Sends that failed since launch. A count only, for the diagnostics report.
    var sendFailures: Int { get }
    /// Every connection opened since the last `startHosting` or `stopAll`, oldest first, ended ones
    /// included. `stopAll` starts a new log; the old one keeps its links, so the diagnostics report
    /// can hold it past Leave and read it after what Leave queued has been sent.
    var linkLog: LinkLog { get }
    /// Host: how often the system reported the room's registration added or removed since the
    /// last `startHosting` or `stopAll`.
    var registrationCounts: RegistrationCounts { get }
}

/// Counts only. A removal before Leave is what decision 2026-10-13 is meant to avoid, so the
/// diagnostics report carries these for a device run to check.
struct RegistrationCounts: Equatable, Sendable {
    var added = 0
    var removed = 0
}

/// The connections of one room, read when the report is made rather than when the room was left:
/// Leave queues an abort and `stopAll` sends it before the links close, and a report taken before
/// that is one frame short (device report 2026-10-11). Bounded, like everything else a peer can cause.
@MainActor
final class LinkLog {
    static let capacity = 32
    private var entries: [() -> LinkReport] = []

    init(_ fixed: [LinkReport] = []) {
        entries = fixed.map { report in { report } }
    }

    /// A lobby that sees many short connections keeps only the most recent ones.
    func add(_ read: @escaping () -> LinkReport) {
        entries.append(read)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    var reports: [LinkReport] { entries.map { $0() } }
}

/// What one connection did, in counts and seconds only: no peer name, address or content, so it
/// can go into a diagnostics report. Device report 2026-10-09: one phone's link to the host went
/// silent in both directions mid-round with no failed send. A send that never finishes shows here
/// directly. A link that went quiet and a host that stopped reading look alike, because a send
/// counts as done once the network stack takes it (see `Outbox.sentCount`); comparing both
/// phones' reports narrows it, it does not settle it.
struct LinkReport: Equatable, Sendable {
    enum End: Equatable, Sendable {
        /// Still open when the report was taken.
        case open
        /// It failed or reset (`Framing.ConnectionEnd.failed`).
        case lost
        /// The other side closed it (`Framing.ConnectionEnd.closed`).
        case closedThere
        /// The other side broke the framing rules.
        case badFrame
        /// A send threw.
        case sendFailed
        /// The queue for it was full: the other side had stopped taking data.
        case queueFull
        /// This phone closed it: a disconnect or a replacement.
        case closedHere
        /// This phone left the room, or started another, with the link still open.
        case leftRoom
    }

    /// The kind of interface the connection ran over, as last seen.
    enum Route: Hashable, Sendable {
        case unknown
        /// Apple's direct phone-to-phone Wi-Fi, which needs no Wi-Fi network.
        case peerToPeer
        /// A Wi-Fi network both phones are on.
        case wifiNetwork
        case wired
        case cellular
        case loopback
        case other
        /// The path listed interfaces of more than one kind, and nothing says which carried it.
        case mixed
    }

    /// True for a joiner's one connection to the host; false for a host's connection to a joiner.
    var toHost: Bool
    var end: End = .open
    var route: Route = .unknown
    /// Times the route moved to another kind of interface after the first one was seen.
    var routeChanges = 0
    /// Times Network said reads and writes would no longer succeed on it (viability went false).
    var timesUnusable = 0
    /// How long the connection had been open when it ended, or when the report was taken.
    var secondsOpen = 0
    var framesSent = 0
    var framesReceived = 0
    /// Frames handed to the connection and not yet taken by the network stack, the one being sent
    /// included.
    var waitingToSend = 0
    /// How long the send in progress has been running, when one is.
    var secondsSending: Int?
    /// Seconds since the last frame arrived, measured at the same point as `secondsOpen`. Nil when
    /// nothing ever arrived.
    var secondsSinceLastReceived: Int?
}
