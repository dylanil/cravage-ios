import XCTest
@testable import CravageCore
@testable import Cravage

/// Which screen a phone shows is a pure function of the round state, so SPEC's confirmation barrier
/// is a routing property as well as an engine one: no phone can be on the figure screen until every
/// phone has confirmed the room code.
@MainActor
final class ScreenRoutingTests: XCTestCase {

    private func startedRoom() async -> FakeStar {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        let host = star.coordinators[0]
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        return star
    }

    func testNoPhoneShowsTheFigureScreenUntilEveryPhoneHasConfirmedTheCode() async {
        let star = await startedRoom()
        for coordinator in star.coordinators {
            XCTAssertEqual(Screen(coordinator), .confirmCode)
        }

        let last = star.coordinators.count - 1
        for (index, coordinator) in star.coordinators.enumerated() {
            coordinator.confirmRoomCode(generation: coordinator.engine.generation)
            star.flush()
            guard index < last else { break }
            for other in star.coordinators {
                XCTAssertNotEqual(Screen(other), .enterFigure,
                                  "a phone left the barrier after \(index + 1) of 3 confirmations")
            }
        }

        for coordinator in star.coordinators {
            XCTAssertEqual(Screen(coordinator), .enterFigure)
        }
    }

    func testTheLobbyScreenFollowsTheRole() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        await star.coordinators[0].createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertEqual(Screen(star.coordinators[0]), .lobbyHost)

        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        XCTAssertEqual(Screen(star.coordinators[1]), .lobbyJoiner)
    }

    func testAPhoneThatSentItsFigureWaitsWhileTheOthersType() async {
        let star = await startedRoom()
        for coordinator in star.coordinators {
            coordinator.confirmRoomCode(generation: coordinator.engine.generation)
        }
        star.flush()

        let first = star.coordinators[0]
        XCTAssertNil(first.submitFigure("10", generation: first.engine.generation))
        star.flush()
        XCTAssertEqual(Screen(first), .waiting, "its own figure is gone; the others have not typed")
        XCTAssertEqual(Screen(star.coordinators[1]), .enterFigure)
    }

    func testAFinishedRoundLandsOnTheResultScreen() async {
        let star = await startedRoom()
        for coordinator in star.coordinators {
            coordinator.confirmRoomCode(generation: coordinator.engine.generation)
        }
        star.flush()
        for (coordinator, text) in zip(star.coordinators, ["10", "20.5", "30"]) {
            XCTAssertNil(coordinator.submitFigure(text, generation: coordinator.engine.generation))
        }
        star.flush()
        for coordinator in star.coordinators {
            XCTAssertEqual(Screen(coordinator), .result(.agreed))
        }
    }

    /// Owner decision 2026-09-13: a joiner is asked before rejoining a restart, so the offer has to
    /// outrank the failure that carries it.
    func testARestartOfferOutranksTheRoundItEnded() {
        let screen = Screen.current(phase: .failed(.hostRestarted), role: .joiner,
                                    hasRestartOffer: true, idle: .home)
        XCTAssertEqual(screen, .restartOffer)
    }

    func testWhileIdleTheScreenIsWhereThePersonNavigated() {
        for idle in [IdleScreen.home, .newRoom, .join] {
            XCTAssertEqual(Screen.current(phase: .idle, role: nil, hasRestartOffer: false, idle: idle),
                           idle.screen)
        }
    }
}
