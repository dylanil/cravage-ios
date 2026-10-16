#if DEBUG
import Foundation
import CravageCore

/// Screenshot staging (PLAN: "deterministic seeded scenarios, launch argument, compiled out of
/// release"). `-cravageStage <scene>` replaces the network with an in-memory room of hidden phones
/// and plays a real round up to that scene, so every screen shows real engine state. Debug builds
/// only: the Release build step in CI checks that the argument name is absent from the binary.
///
/// The clock is frozen, so countdowns read their full deadline and nothing expires mid-capture.
/// Room codes come from fresh random keys and differ between runs. Letters follow the keys too, so
/// from Check the code on the stage replays the room until they follow the names; everything else
/// is fixed.
@MainActor
final class ScreenshotStage {
    enum Scene: String, CaseIterable {
        case home, newRoom, lobby, confirmCode, enterFigure, waiting, result
    }

    static let argument = "cravageStage"
    static let label = "Weekly screen time"
    static let others = ["Bob", "Carol"]
    static let figures = ["12", "6", "8.5"]

    /// Tries at the room before the last one stands; each has a one-in-six chance of name order.
    static let replays = 100

    let scene: Scene
    /// The visible phone. `run` may swap in a fresh room's host; the app shows the one it ends with.
    private(set) var coordinator: RoundCoordinator
    let store: StoreManager
    private var star: Star
    private var played = false

    /// The figure the Enter figure screen starts with: the host's, typed in but not sent.
    static func draftFigure(for scene: Scene) -> String? {
        scene == .enterFigure ? figures[0] : nil
    }

    /// Nil unless the app was launched with `-cravageStage <scene>`.
    static func fromLaunchArguments() -> ScreenshotStage? {
        launchScene.map(ScreenshotStage.init(scene:))
    }

    /// The scene named by `-cravageStage`, if any.
    static var launchScene: Scene? {
        UserDefaults.standard.string(forKey: argument).flatMap(Scene.init(rawValue:))
    }

    init(scene: Scene) {
        self.scene = scene
        star = Star(phones: 1 + Self.others.count)
        coordinator = star.coordinators[0]
        store = StoreManager(backend: StagedStore())
    }

    var idle: IdleScreen { scene == .newRoom ? .newRoom : .home }

    /// Plays the round to the scene, once: SwiftUI may start a view's task again, and a second
    /// pass would admit the person the lobby keeps at the door. The visible phone hosts; the hidden
    /// ones join.
    func run(hostNickname: String) async {
        guard !played else { return }
        played = true
        guard ![.home, .newRoom].contains(scene) else { return }
        await openRoom(hostNickname: hostNickname)
        guard scene != .lobby else { return }
        startRound()
        // The listing shows Alice, Bob and Carol in that order (decision 2026-10-05).
        var tries = 1
        while coordinator.engine.roster?.parties.map(\.nickname) != [hostNickname] + Self.others,
              tries < Self.replays {
            star = Star(phones: 1 + Self.others.count)
            coordinator = star.coordinators[0]
            await openRoom(hostNickname: hostNickname)
            startRound()
            tries += 1
        }
        let host = coordinator
        guard scene != .confirmCode else { return }
        for phone in star.coordinators { phone.confirmRoomCode(generation: phone.engine.generation) }
        star.flush()
        guard scene != .enterFigure else { return }
        host.submitFigure(Self.figures[0], generation: host.engine.generation)
        star.flush()
        guard scene != .waiting else { return }
        for (phone, figure) in zip(star.coordinators.dropFirst(), Self.figures.dropFirst()) {
            phone.submitFigure(figure, generation: phone.engine.generation)
        }
        star.flush()
    }

    /// The hidden phones join; the lobby shows one person admitted and one waiting at the door.
    private func openRoom(hostNickname: String) async {
        let host = coordinator
        await host.createRoom(label: Self.label, size: 1 + Self.others.count, nickname: hostNickname)
        for (offset, name) in Self.others.enumerated() {
            star.coordinators[offset + 1].join(roomID: "room", nickname: name)
            star.flush()
        }
        let pending = host.engine.pendingJoiners
        for joiner in scene == .lobby ? Array(pending.prefix(1)) : pending {
            host.admit(joiner.verifyingKey, generation: host.engine.generation)
        }
        star.flush()
    }

    private func startRound() {
        coordinator.start(generation: coordinator.engine.generation)
        star.flush()
    }
}

/// Time stands still: deadlines are read but never reached.
@MainActor
private final class FrozenClock: RoundClock {
    func nowMs() -> UInt64 { 1_000 }
    func sleep(untilMs: UInt64) async throws { try await Task.sleep(for: .seconds(86_400 * 365)) }
}

/// A store that knows the unlock's price and that this phone has not bought it. The price is 0.99 in
/// the simulator's own currency, so the symbol matches the locale; the App Store's real figure
/// varies by region.
@MainActor
private final class StagedStore: StoreBackend {
    func displayPrice(for productID: String) async throws -> String? {
        0.99.formatted(.currency(code: Locale.current.currency?.identifier ?? "GBP"))
    }
    func purchase(_ productID: String) async throws -> PurchaseOutcome { .cancelled }
    func currentEntitlements() async -> [UnlockRecord] { [] }
    func updates() -> AsyncStream<UnlockRecord> { AsyncStream { _ in } }
    func sync() async throws {}
}

@MainActor
private final class Unentitled: EntitlementProvider {
    func hasVerifiedUnlock() async -> Bool { false }
}

/// An in-memory star: phone 0 hosts, the others join. Deliveries are queued and flushed so no
/// coordinator is re-entered while it is still carrying out effects.
///
/// Simpler than the tests' FakeStar: it has no notion of a dropped link, because no staged scene
/// declines, leaves or fails. A scene that disconnects anyone stops here rather than capture a room
/// this star cannot model.
@MainActor
private final class Star {
    final class Transport: RoundTransport {
        var onEvent: ((TransportEvent) -> Void)?
        weak var star: Star?
        let index: Int
        let sendFailures = 0
        let linkLog = LinkLog()
        let registrationCounts = RegistrationCounts()
        init(index: Int) { self.index = index }
        func startHosting(label: String, size: Int, hostNickname: String) {}
        func closeListing() {}
        func startBrowsing() {}
        func connect(to roomID: String) { star?.connect(joiner: index) }
        func send(_ data: Data, to peer: PeerID) { star?.enqueue(from: index, to: peer, data) }
        func disconnect(_ peer: PeerID) { preconditionFailure("staged scenes never disconnect a phone") }
        func stopAll() {}
    }

    let transports: [Transport]
    var coordinators: [RoundCoordinator] = []
    private var queue: [(to: Int, event: TransportEvent)] = []

    init(phones: Int) {
        transports = (0..<phones).map { Transport(index: $0) }
        let clock = FrozenClock()
        for transport in transports {
            transport.star = self
            // Staged phones leave the phone's own screen setting alone.
            coordinators.append(RoundCoordinator(transport: transport, clock: clock, entitlement: Unentitled(),
                                                 keepScreenAwake: { _ in }))
        }
    }

    func connect(joiner: Int) { queue.append((0, .peerConnected(PeerID(joiner)))) }

    func enqueue(from: Int, to peer: PeerID, _ data: Data) {
        queue.append((from == 0 ? peer.raw : 0, .received(data, from: from == 0 ? .host : PeerID(from))))
    }

    func flush() {
        while !queue.isEmpty {
            let item = queue.removeFirst()
            transports[item.to].onEvent?(item.event)
        }
    }
}
#endif
