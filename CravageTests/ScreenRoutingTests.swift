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

    /// Found on three phones: a host restarted and could not readmit anyone, because the screen a
    /// joiner needs in order to accept was never built and its Back button left the room.
    func testAHostRestartOffersEveryJoinerARejoinTheyCanAccept() async {
        let star = await startedRoom()
        for coordinator in star.coordinators {
            coordinator.confirmRoomCode(generation: coordinator.engine.generation)
        }
        star.flush()
        for (coordinator, text) in zip(star.coordinators, ["10", "20.5", "30"]) {
            XCTAssertNil(coordinator.submitFigure(text, generation: coordinator.engine.generation))
        }
        star.flush()

        let host = star.coordinators[0]
        host.restart(generation: host.engine.generation)
        star.flush()

        for joiner in star.coordinators.dropFirst() {
            XCTAssertEqual(Screen(joiner), .restartOffer, "the joiner was never asked")
            joiner.acceptRestart(generation: joiner.engine.generation)
        }
        star.flush()

        // SPEC 13: the restarted round warns before anything can be sent, on every phone.
        for coordinator in star.coordinators {
            XCTAssertEqual(Screen(coordinator), .restartWarning,
                           "a restarted round went on without warning")
            XCTAssertEqual(Screen(coordinator, warningAcknowledgedFor: coordinator.engine.generation),
                           .confirmCode,
                           "the restarted round did not reach the code check once acknowledged")
        }
    }

    /// The warning belongs to restarts only; a first round goes straight to the code check.
    func testAFirstRoundIsNeverWarnedAboutARestart() async {
        let star = await startedRoom()
        for coordinator in star.coordinators {
            XCTAssertFalse(coordinator.engine.restartWarningRequired)
            XCTAssertEqual(Screen(coordinator), .confirmCode)
        }
    }

    /// Acknowledging one restart does not silence the next: the flag is per round generation.
    func testEachRestartWarnsAgain() {
        let warned = Screen.current(phase: .confirming, role: .joiner, hasRestartOffer: false,
                                    restartWarningRequired: true, restartWarningAcknowledged: false,
                                    idle: .home)
        XCTAssertEqual(warned, .restartWarning)
        let acknowledged = Screen.current(phase: .confirming, role: .joiner, hasRestartOffer: false,
                                          restartWarningRequired: true, restartWarningAcknowledged: true,
                                          idle: .home)
        XCTAssertEqual(acknowledged, .confirmCode)
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
