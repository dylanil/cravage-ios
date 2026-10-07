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

    /// The engine refuses a round smaller than the size the host chose, so the button waits for it.
    func testStartWaitsUntilTheRoomIsFull() {
        XCTAssertFalse(Lobby.canStart(inRoom: 1, maxSize: 3))
        XCTAssertFalse(Lobby.canStart(inRoom: 2, maxSize: 3))
        XCTAssertTrue(Lobby.canStart(inRoom: 3, maxSize: 3))
        XCTAssertFalse(Lobby.canStart(inRoom: 4, maxSize: 3), "a room cannot start over its size")
        XCTAssertFalse(Lobby.canStart(inRoom: 3, maxSize: 6), "a room for 6 never runs with 3")
        XCTAssertFalse(Lobby.canStart(inRoom: 5, maxSize: 6))
        XCTAssertTrue(Lobby.canStart(inRoom: 6, maxSize: 6))
    }

    func testTheHintCountsTheRoomAndNamesTheNextPersonToAdmit() {
        XCTAssertEqual(Lobby.startHint(inRoom: 2, maxSize: 3, pending: ["Priya"]),
                       "Start needs all 3 people. 2 are in. Admit Priya to begin.")
        XCTAssertEqual(Lobby.startHint(inRoom: 2, maxSize: 3, pending: []),
                       "Start needs all 3 people. 2 are in.")
        XCTAssertEqual(Lobby.startHint(inRoom: 3, maxSize: 6, pending: ["Priya", "Sam"]),
                       "Start needs all 6 people. 3 are in. Admit Priya next.")
        XCTAssertEqual(Lobby.startHint(inRoom: 1, maxSize: 4, pending: []),
                       "Start needs all 4 people. Only you are in.")
        XCTAssertNil(Lobby.startHint(inRoom: 3, maxSize: 3, pending: []))
        XCTAssertNil(Lobby.startHint(inRoom: 6, maxSize: 6, pending: []))
    }

    func testTheConnectedLineCountsPhonesNotPeople() {
        XCTAssertEqual(Lobby.connectedLine(others: 1),
                       "1 other phone connected. Keep the app open on every phone until the round ends.")
        XCTAssertEqual(Lobby.connectedLine(others: 2),
                       "2 other phones connected. Keep the app open on every phone until the round ends.")
    }

    /// A refused tap in the lobby says why; before 2026-09-24 the screen showed nothing at all.
    func testEveryLobbyRefusalSaysWhy() {
        XCTAssertNil(Lobby.refusal(nil, maxSize: 3))
        XCTAssertEqual(Lobby.refusal(.roomFull, maxSize: 3), "This room is set for 3 people and is full.")
        XCTAssertEqual(Lobby.refusal(.notEnoughPeople, maxSize: 6), "Start needs all 6 people.")
        for rejection: Rejection in [.notEnoughPeople, .invalidInput, .wrongPhase, .notEntitled, .staleGeneration, .queueFull] {
            XCTAssertNotNil(Lobby.refusal(rejection, maxSize: 3), "\(rejection) was silent")
        }
    }

    /// Admitting one person too many is refused by the engine, and the refusal reaches the screen.
    func testAdmittingIntoAFullRoomIsReported() async {
        let star = FakeStar(phones: 4, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee"), (3, "Kim")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
        }
        star.flush()
        for _ in 0..<2 {
            host.admit(host.engine.pendingJoiners[0].verifyingKey, generation: host.engine.generation)
        }
        XCTAssertNil(host.lastRejection)
        host.admit(host.engine.pendingJoiners[0].verifyingKey, generation: host.engine.generation)
        XCTAssertEqual(host.lastRejection, .roomFull)
        XCTAssertEqual(Lobby.refusal(host.lastRejection, maxSize: host.engine.maxSize), "This room is set for 3 people and is full.")
    }

    /// Admit all appears only when the people waiting fill the room exactly: never a choice of who
    /// to leave out, and never for one person, where Admit already does it.
    func testAdmitAllOnlyWhenTheWaitingFillTheRoomExactly() {
        XCTAssertTrue(Lobby.canAdmitAll(inRoom: 1, maxSize: 3, pending: 2))
        XCTAssertTrue(Lobby.canAdmitAll(inRoom: 2, maxSize: 4, pending: 2))
        XCTAssertTrue(Lobby.canAdmitAll(inRoom: 1, maxSize: 8, pending: 7))
        XCTAssertFalse(Lobby.canAdmitAll(inRoom: 1, maxSize: 4, pending: 2), "two of three seats")
        XCTAssertFalse(Lobby.canAdmitAll(inRoom: 1, maxSize: 3, pending: 3), "more waiting than seats")
        XCTAssertFalse(Lobby.canAdmitAll(inRoom: 2, maxSize: 3, pending: 1), "one person: Admit does it")
        XCTAssertFalse(Lobby.canAdmitAll(inRoom: 3, maxSize: 3, pending: 0))
    }

    func testAdmitAllAdmitsEveryoneTheHostSaw() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        defer { star.coordinators.forEach { $0.leave() } }
        await host.createRoom(label: "Team", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        RoundActions(host).admitAll(shown: host.engine.pendingJoiners.map(\.verifyingKey))
        star.flush()
        XCTAssertEqual(host.engine.admittedNicknames, ["Alex", "Dee"])
        XCTAssertEqual(host.engine.pendingJoiners.count, 0)
        XCTAssertNil(host.lastRejection)
    }

    /// The list on screen is what the host checked against the room. If it changed before the tap,
    /// nobody is admitted: the host has not seen the new list.
    func testAdmitAllAdmitsNobodyWhenTheListChangedBeforeTheTap() async {
        let star = FakeStar(phones: 4, entitlement: FakeEntitlement(unlocked: true))
        let host = star.coordinators[0]
        defer { star.coordinators.forEach { $0.leave() } }
        await host.createRoom(label: "Team", size: 4, nickname: "Sam")
        star.coordinators[1].join(roomID: "room", nickname: "Alex")
        star.flush()
        host.admit(host.engine.pendingJoiners[0].verifyingKey, generation: host.engine.generation)
        for (index, name) in [(2, "Dee"), (3, "Kim")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        let shown = host.engine.pendingJoiners.map(\.verifyingKey)
        star.coordinators[3].leave()
        star.flush()
        star.coordinators[3].join(roomID: "room", nickname: "Kim")
        star.flush()
        XCTAssertEqual(host.engine.pendingJoiners.count, 2, "Kim is back, under a new key")
        RoundActions(host).admitAll(shown: shown)
        star.flush()
        XCTAssertEqual(host.engine.admittedNicknames, ["Alex"])
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

    /// The confirm screen marks a row "Host" from this, and the review found it untested. A joiner
    /// derives it from the welcome it verified; the host from its own letter. They must agree.
    func testEveryPhoneAgreesWhichLetterIsTheHost() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Annual bonus", size: 3, nickname: "Sam")
        for (index, name) in [(1, "Alex"), (2, "Dee")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        XCTAssertNil(host.engine.hostLetter, "there are no letters before the roster locks")

        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()

        let letter = host.engine.hostLetter
        XCTAssertNotNil(letter)
        XCTAssertEqual(letter, host.engine.myLetter, "the host is itself")
        for joiner in star.coordinators.dropFirst() {
            XCTAssertEqual(joiner.engine.hostLetter, letter, "a joiner named a different host")
            XCTAssertNotEqual(joiner.engine.myLetter, letter)
        }
        XCTAssertEqual(host.engine.roster?.party(letter!).nickname, "Sam")
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
