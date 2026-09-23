import XCTest
import SwiftUI
import UIKit
@testable import CravageCore
@testable import Cravage

@MainActor
final class RoundActionsTests: XCTestCase {
    func testCancelledCreationCleanupCannotClearANewerCreation() async throws {
        let store = FakeEntitlement(unlocked: true)
        store.holdAnswer = true
        let star = FakeStar(phones: 1, entitlement: store)
        let host = star.coordinators[0]
        defer { host.leave() }
        let oldScreen = RoundActions(host)
        let oldCreation = Task { await oldScreen.createRoom(label: "Old", size: 4, nickname: "Host") }
        for _ in 0..<100 where store.gate == nil { await Task.yield() }
        let oldAnswer = try XCTUnwrap(store.gate)
        oldScreen.leave()
        store.gate = nil
        let current = RoundActions(host)
        let newCreation = Task { await current.createRoom(label: "New", size: 4, nickname: "Host") }
        for _ in 0..<100 where store.gate == nil { await Task.yield() }
        let newAnswer = store.gate
        oldAnswer.resume()
        await oldCreation.value
        XCTAssertNotNil(newAnswer)
        XCTAssertTrue(host.isCreatingRoom, "old cleanup must not clear the newer operation's busy flag")
        XCTAssertEqual(host.engine.phase, .idle)
        newAnswer?.resume()
        await newCreation.value
        XCTAssertFalse(host.isCreatingRoom)
        XCTAssertEqual(host.engine.label, "New")
    }

    func testCancelledEntitlementCheckDoesNotBlockANewFreeRoom() async {
        let store = FakeEntitlement(unlocked: true)
        store.holdAnswer = true
        let star = FakeStar(phones: 1, entitlement: store)
        let host = star.coordinators[0]
        defer { host.leave() }
        let oldScreen = RoundActions(host)
        let oldCreation = Task { await oldScreen.createRoom(label: "Old", size: 4, nickname: "Host") }
        for _ in 0..<100 where store.gate == nil { await Task.yield() }
        XCTAssertNotNil(store.gate)
        oldScreen.leave()
        await RoundActions(host).createRoom(label: "New", size: 3, nickname: "Host")
        XCTAssertEqual(host.engine.phase, .lobby)
        XCTAssertEqual(host.engine.label, "New")
        store.gate?.resume()
        await oldCreation.value
        XCTAssertEqual(host.engine.label, "New", "a cancelled store answer cannot replace the new room")
    }

    func testCancelledScreenCannotOpenOrJoinARoomLater() async {
        for joining in [false, true] {
            let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
            let phone = star.coordinators[0]
            defer { phone.leave() }
            let oldScreen = RoundActions(phone)
            XCTAssertTrue(oldScreen.leave())
            if joining {
                oldScreen.join(roomID: "room", nickname: "Person")
            } else {
                await oldScreen.createRoom(label: "Room", size: 3, nickname: "Host")
            }
            XCTAssertEqual(phone.engine.phase, .idle)
            XCTAssertNil(star.transports[0].hosting)
            XCTAssertEqual(star.transports[0].connectionAttempts, 0)
            oldScreen.browse()
            XCTAssertFalse(star.transports[0].browsing)
        }
    }

    func testOldCancelCannotCancelANewerPendingRoomCreation() async {
        let store = FakeEntitlement(unlocked: true)
        store.holdAnswer = true
        let star = FakeStar(phones: 1, entitlement: store)
        let host = star.coordinators[0]
        defer { host.leave() }
        let oldScreen = RoundActions(host)
        XCTAssertTrue(oldScreen.leave())
        let current = RoundActions(host)
        let creation = Task { await current.createRoom(label: "Room", size: 4, nickname: "Host") }
        for _ in 0..<100 where store.gate == nil { await Task.yield() }
        XCTAssertNotNil(store.gate)
        XCTAssertFalse(oldScreen.leave())
        store.gate?.resume()
        await creation.value
        XCTAssertEqual(host.engine.phase, .lobby)
        XCTAssertNotNil(star.transports[0].hosting)
    }

    func testBackgroundInvalidatesOpenQueuedBeforeItReachesTheCoordinator() async {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        defer { host.leave() }
        let screen = RoundActions(host)
        let creation = Task { await screen.createRoom(label: "Room", size: 3, nickname: "Host") }
        host.appEnteredBackground()
        await creation.value
        XCTAssertEqual(host.engine.phase, .idle)
        XCTAssertNil(star.transports[0].hosting)
    }

    private func startedRoom() async -> FakeStar {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Round", size: 3, nickname: "Host")
        for index in 1...2 {
            star.coordinators[index].join(roomID: "room", nickname: "Person \(index)")
            star.flush()
        }
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        return star
    }

    func testRetainedScreenActionsCannotActOnTheNextRound() async {
        let star = await startedRoom()
        defer { star.coordinators.forEach { $0.leave() } }
        let host = star.coordinators[0]
        let oldScreen = RoundActions(host)
        oldScreen.restart()
        star.flush()
        for joiner in star.coordinators.dropFirst() {
            RoundActions(joiner).acceptRestart()
        }
        star.flush()
        let nextGeneration = host.engine.generation
        XCTAssertEqual(Screen(host), .restartWarning)

        oldScreen.acknowledgeRestartWarning()
        XCTAssertEqual(Screen(host), .restartWarning, "the old warning cannot acknowledge a new round")
        oldScreen.confirmRoomCode()
        XCTAssertFalse(host.engine.localConfirmed, "the old code cannot confirm a new roster")
        oldScreen.restart()
        XCTAssertEqual(host.engine.generation, nextGeneration, "the old result cannot restart the new round")
        XCTAssertFalse(oldScreen.leave(), "an old Leave button cannot close a new room")
        XCTAssertEqual(host.engine.phase, .confirming)

        let currentScreen = RoundActions(host)
        currentScreen.acknowledgeRestartWarning()
        XCTAssertEqual(Screen(host), .confirmCode)
        currentScreen.confirmRoomCode()
        XCTAssertTrue(host.engine.localConfirmed)
    }

    func testRunAgainRefusalChangesTheRenderedResult() async throws {
        let star = await startedRoom()
        defer { star.coordinators.forEach { $0.leave() } }
        for phone in star.coordinators { RoundActions(phone).confirmRoomCode() }
        star.flush()
        for phone in star.coordinators { RoundActions(phone).submitFigure("10") }
        star.flush()
        let host = star.coordinators[0]
        XCTAssertEqual(host.engine.phase, .complete(.agreed))
        star.coordinators[2].leave()
        star.flush()
        let actions = RoundActions(host)
        func renderedResult() throws -> Data {
            let view = ResultView(coordinator: host, outcome: .agreed,
                                  onRunAgain: actions.restart, onLeave: {})
                .frame(width: 390, height: 844)
            return try XCTUnwrap(ImageRenderer(content: view).uiImage?.pngData())
        }
        let before = try renderedResult()
        actions.restart()
        XCTAssertEqual(host.lastRejection, .notEnoughPeople)
        XCTAssertEqual(host.engine.phase, .complete(.agreed))
        XCTAssertNotEqual(try renderedResult(), before, "a refused Run again must visibly explain the next step")
    }

    func testMountedResultUpdatesAfterARefusedRestart() async throws {
        let star = await startedRoom()
        defer { star.coordinators.forEach { $0.leave() } }
        for phone in star.coordinators { RoundActions(phone).confirmRoomCode() }
        star.flush()
        for phone in star.coordinators { RoundActions(phone).submitFigure("10") }
        star.flush()
        let host = star.coordinators[0]
        star.coordinators[2].leave()
        star.flush()
        let actions = RoundActions(host)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            ResultView(coordinator: host, outcome: .agreed, onRunAgain: actions.restart, onLeave: {}))
        window.isHidden = false
        defer { window.isHidden = true }
        func pixels() throws -> Data {
            window.layoutIfNeeded()
            return try XCTUnwrap(UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                window.layer.render(in: context.cgContext)
            }.pngData())
        }
        try await Task.sleep(for: .milliseconds(50))
        let before = try pixels()
        actions.restart()
        XCTAssertEqual(host.lastRejection, .notEnoughPeople)
        // Keep the same hosted view. Allow SwiftUI to deliver its observed update; do not
        // manufacture a new ResultView after the rejection as the static rendering test does.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            if try pixels() != before { return }
        }
        XCTFail("the mounted result never displayed its restart refusal")
    }

    func testFigureControlsEnterAnExactNegativeDecimal() async {
        let star = await startedRoom()
        defer { star.coordinators.forEach { $0.leave() } }
        for phone in star.coordinators { RoundActions(phone).confirmRoomCode() }
        star.flush()
        var text = FigureEditing.changingSign("12")
        text = FigureEditing.appendingDecimalPoint(text) + "345678"
        XCTAssertEqual(text, "-12.345678")
        XCTAssertEqual(FigureEditing.changingSign(text), "12.345678")
        XCTAssertEqual(FigureEditing.changingSign("+12"), "-12")
        XCTAssertEqual(FigureEditing.changingSign(""), "-")
        XCTAssertEqual(FigureEditing.appendingDecimalPoint(text), "-12.345678")
        XCTAssertEqual(FigureEditing.appendingDecimalPoint("1,2"), "1,2",
                       "never silently reinterpret a pasted comma")
        for phone in star.coordinators { XCTAssertNil(RoundActions(phone).submitFigure(text)) }
        star.flush()
        for phone in star.coordinators {
            XCTAssertEqual(phone.engine.phase, .complete(.agreed))
            XCTAssertEqual(phone.engine.average, "-12.35")
        }
    }

    func testBackgroundingEitherRoleEndsAnUnfinishedRoundOnEveryPhone() async {
        for index in [0, 1] {
            let star = await startedRoom()
            defer { star.coordinators.forEach { $0.leave() } }
            for phone in star.coordinators { RoundActions(phone).confirmRoomCode() }
            star.flush()
            // One share has gone; the round must not continue after a phone locks.
            RoundActions(star.coordinators[2]).submitFigure("10")
            star.flush()
            star.coordinators[index].appEnteredBackground()
            star.flush()
            XCTAssertEqual(Screen(star.coordinators[index]), .interrupted)
            XCTAssertEqual(star.coordinators[index].engine.phase, .idle)
            XCTAssertNil(star.coordinators[index].engine.session)
            XCTAssertNil(star.coordinators[index].engine.record)
            for (otherIndex, phone) in star.coordinators.enumerated() where otherIndex != index {
                guard case .failed = phone.engine.phase else {
                    XCTFail("an unfinished round survived a phone entering the background")
                    continue
                }
            }
        }
    }

    func testBackgroundCancelsARestartOfferAndItsOldRejoinButton() async {
        let star = await startedRoom()
        defer { star.coordinators.forEach { $0.leave() } }
        RoundActions(star.coordinators[0]).restart()
        star.flush()
        let joiner = star.coordinators[1]
        XCTAssertEqual(Screen(joiner), .restartOffer)
        let oldOffer = RoundActions(joiner)
        joiner.appEnteredBackground()
        oldOffer.acceptRestart()
        star.flush()
        XCTAssertEqual(Screen(joiner), .interrupted)
        XCTAssertEqual(joiner.engine.phase, .idle)
        XCTAssertNil(joiner.engine.restartOffer)
        XCTAssertFalse(star.connected.contains(1))
        RoundActions(joiner).leave()
        XCTAssertEqual(Screen(joiner), .home)
    }

    func testBackgroundCancelsAPendingRoomCreation() async {
        let store = FakeEntitlement(unlocked: true)
        store.holdAnswer = true
        let star = FakeStar(phones: 1, entitlement: store)
        let host = star.coordinators[0]
        let creation = Task { await host.createRoom(label: "Room", size: 4, nickname: "Host") }
        for _ in 0..<100 where store.gate == nil { await Task.yield() }
        XCTAssertNotNil(store.gate)
        host.appEnteredBackground()
        store.gate?.resume()
        await creation.value
        XCTAssertEqual(host.engine.phase, .idle)
        XCTAssertNil(star.transports[0].hosting)
        XCTAssertEqual(Screen(host), .interrupted)
        host.leave()
    }

    func testBackgroundKeepsAnAlreadyFinishedResultAvailableForSharing() async {
        let star = await startedRoom()
        defer { star.coordinators.forEach { $0.leave() } }
        for phone in star.coordinators { RoundActions(phone).confirmRoomCode() }
        star.flush()
        for phone in star.coordinators { RoundActions(phone).submitFigure("10") }
        star.flush()
        for phone in star.coordinators {
            phone.appEnteredBackground()
            XCTAssertEqual(Screen(phone), .result(.agreed))
            XCTAssertNotNil(phone.engine.record.flatMap(Transcript.make))
        }
    }
}
