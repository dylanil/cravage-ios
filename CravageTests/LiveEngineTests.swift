import XCTest
import Observation
@testable import CravageCore
@testable import Cravage

/// `RoundEngine` is a plain class, so reading it straight off the coordinator registers nothing
/// with SwiftUI and a screen never re-renders when the round moves. Views read it through
/// `coordinator.live`, which touches the observable `revision` first.
/// `onChange` runs outside the actor, so the flag it sets lives in a box.
private final class Flag: @unchecked Sendable {
    var value = false
}

@MainActor
final class LiveEngineTests: XCTestCase {

    func testReadingTheEngineThroughLiveNotifiesAWatcher() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        let notified = Flag()
        withObservationTracking {
            _ = host.live.phase
        } onChange: {
            notified.value = true
        }

        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertTrue(notified.value, "a screen reading the round through live would not have re-rendered")
    }

    /// The reason `live` exists: this is what every screen would otherwise do.
    func testReadingTheEngineDirectlyNotifiesNobody() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        let notified = Flag()
        withObservationTracking {
            _ = host.engine.phase
        } onChange: {
            notified.value = true
        }

        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertFalse(notified.value, "if this ever notifies, RoundEngine became observable and live can go")
    }

    /// The failure this guards: RootView switches on `Screen(coordinator)`, so if that read is not
    /// observed the app draws Home and stays there however far the round gets.
    func testTheRoutingReadNotifiesWhenTheRoundMoves() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        let notified = Flag()
        withObservationTracking {
            _ = Screen(host)
        } onChange: {
            notified.value = true
        }

        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertTrue(notified.value, "the app would have stayed on the screen it opened with")
    }

    /// The lobby's own content, not just the routing: a joiner asking to join has to reach the host.
    func testAJoinerArrivingNotifiesAWatcherOfTheLobby() async {
        let star = FakeStar(phones: 2, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")

        let notified = Flag()
        withObservationTracking {
            _ = host.live.pendingJoiners.count
        } onChange: {
            notified.value = true
        }

        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        XCTAssertTrue(notified.value, "the host's lobby would not have shown the request")
    }
}
