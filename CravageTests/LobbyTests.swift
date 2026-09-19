import XCTest
@testable import CravageCore
@testable import Cravage

@MainActor
final class LobbyTests: XCTestCase {

    func testTheCountdownReadsAsMinutesAndSeconds() {
        XCTAssertEqual(Countdown.text(seconds: 852), "14:12")
        XCTAssertEqual(Countdown.text(seconds: 168), "2:48")
        XCTAssertEqual(Countdown.text(seconds: 9), "0:09")
        XCTAssertEqual(Countdown.text(seconds: 0), "0:00")
        XCTAssertEqual(Countdown.text(seconds: -5), "0:00", "an expired deadline never reads negative")
    }

    /// The engine refuses a round smaller than the smallest roster, so the button waits for it.
    func testStartWaitsForTheSmallestRosterTheProtocolAllows() {
        XCTAssertFalse(Lobby.canStart(inRoom: 1, maxSize: 3))
        XCTAssertFalse(Lobby.canStart(inRoom: 2, maxSize: 3))
        XCTAssertTrue(Lobby.canStart(inRoom: 3, maxSize: 3))
        XCTAssertFalse(Lobby.canStart(inRoom: 4, maxSize: 3), "a room cannot start over its size")
        XCTAssertTrue(Lobby.canStart(inRoom: 4, maxSize: 8))
    }

    func testTheHintNamesTheNextPersonToAdmit() {
        XCTAssertEqual(Lobby.startHint(inRoom: 2, maxSize: 3, pending: ["Priya"]),
                       "Start needs 3 people. Admit Priya to begin.")
        XCTAssertEqual(Lobby.startHint(inRoom: 2, maxSize: 3, pending: []),
                       "Start needs 3 people.")
        XCTAssertNil(Lobby.startHint(inRoom: 3, maxSize: 3, pending: []))
    }

    func testTheConnectedLineCountsPhonesNotPeople() {
        XCTAssertEqual(Lobby.connectedLine(others: 1),
                       "1 other phone connected. Keep the app open on every phone until the round ends.")
        XCTAssertEqual(Lobby.connectedLine(others: 2),
                       "2 other phones connected. Keep the app open on every phone until the round ends.")
    }

    /// The host's lobby lists who is in the room; the engine is the only place that knows.
    func testAdmittedNicknamesFollowAdmission() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertEqual(host.engine.admittedNicknames, [])

        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        XCTAssertEqual(host.engine.admittedNicknames, [], "asking to join is not being in the room")

        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        star.flush()
        XCTAssertEqual(host.engine.admittedNicknames, ["Alex", "Dee"])
    }

    func testTheCountdownFollowsTheEngineDeadline() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        XCTAssertNil(host.secondsRemaining(), "nothing is waiting before a room exists")

        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        XCTAssertEqual(host.secondsRemaining(), 600, "the lobby deadline is ten minutes here")
        await star.clock.advance(ms: 599_500)
        XCTAssertEqual(host.secondsRemaining(), 1, "rounded up until it actually expires")
    }
}
