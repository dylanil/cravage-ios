import XCTest
@testable import CravageCore
@testable import Cravage

/// CONTRIBUTING.md: figures, keys, masks, names and labels never appear in logs, diagnostics or crash
/// annotations. The report is meant to be pasted into a support email by someone who cannot read
/// it, so this is the one test that has to hold whatever else changes.
@MainActor
final class DiagnosticsTests: XCTestCase {

    private func roundInProgress(sendFailuresBefore: Int = 0) async -> FakeStar {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        star.transports[0].sendFailures = sendFailuresBefore
        let host = star.coordinators[0]
        await host.createRoom(label: "Quarterly bonus review", size: 3, nickname: "Zebediah")
        for (index, name) in [(1, "Wilhelmina"), (2, "Bartholomew")] {
            star.coordinators[index].join(roomID: "room", nickname: name)
            star.flush()
        }
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        for coordinator in star.coordinators {
            coordinator.confirmRoomCode(generation: coordinator.engine.generation)
        }
        star.flush()
        host.submitFigure("98765.43", generation: host.engine.generation)
        star.flush()
        return star
    }

    func testTheReportCarriesNoNicknameRoomNameFigureOrKey() async {
        let star = await roundInProgress()
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                       build: "1", systemVersion: "26.6", model: "iPhone17,1")

        for secret in ["Zebediah", "Wilhelmina", "Bartholomew", "Quarterly bonus review",
                       "98765", "98765.43"] {
            XCTAssertFalse(report.contains(secret),
                           "the report leaked \(secret.debugDescription):\n\(report)")
        }
    }

    /// The room code and roster hash identify a round and appear in an exported transcript; a
    /// support report is not a transcript and has no reason to carry them.
    func testTheReportCarriesNoRoomCodeOrRosterHash() async {
        let star = await roundInProgress()
        let engine = star.coordinators[0].engine
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")

        let code = engine.roomCode!.code
        XCTAssertFalse(report.contains(code), "the report leaked the room code")
        XCTAssertFalse(report.contains(engine.roster!.rosterHash.base64EncodedString()),
                       "the report leaked the roster hash")
        for letter in engine.roster!.parties.map(\.label.description) {
            XCTAssertFalse(report.contains("party \(letter)"), "the report named a party letter")
        }
    }

    /// It still has to be worth sending: a report that says nothing cannot be diagnosed from.
    func testTheReportSaysEnoughToBeWorthSending() async {
        let star = await roundInProgress()
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")

        XCTAssertTrue(report.contains("0.1"), "no app version")
        XCTAssertTrue(report.contains("iPhone17,1"), "no device model")
        XCTAssertTrue(report.contains("26.6"), "no iOS version")
        XCTAssertTrue(report.contains("host"), "no role")
        XCTAssertTrue(report.contains("sharing"), "no phase")
        XCTAssertTrue(report.contains("3"), "no party count")
    }

    /// Review 2026-10-04: a phone that stops receiving mid-round could be a failed send, the
    /// engine refusing messages, or a stalled screen. The report must tell them apart, so it counts
    /// failed sends next to the confirmed count and the last refused message.
    func testTheReportCountsFailedSends() {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        star.transports[0].sendFailures = 2
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("send failures: 2"), report)
    }

    /// Device reports 2026-10-04 and 2026-10-09: Copy diagnostics is in Settings, reachable only after
    /// leaving, and leaving resets the round, so every report came back "role none, phase idle".
    /// The report has to remember the round it left.
    func testTheLastRoundSurvivesLeaving() async {
        let star = await roundInProgress()
        star.clock.now += 42_000
        star.coordinators[0].leave()
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")

        XCTAssertTrue(report.contains("phase: idle"), "the current state comes first:\n\(report)")
        guard let section = report.range(of: "last round:") else {
            return XCTFail("no last round after leaving:\n\(report)")
        }
        let last = String(report[section.upperBound...])
        for line in ["role: host", "phase: sharing", "parties: 3", "confirmed: 3", "shares in: 1",
                     "since roster locked: 42 s", "own share sent after: 0 s"] {
            XCTAssertTrue(last.contains(line), "last round lacks \(line.debugDescription):\n\(report)")
        }
    }

    /// Review of e833da5: a figure typed while the room code is still being confirmed is only held;
    /// the share leaves when every phone has confirmed. A round stuck there sent nothing, and the
    /// report must not say it did.
    func testAFigureHeldBeforeTheCodeIsConfirmedIsNotReportedAsSent() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Lunch", size: 3, nickname: "Host")
        for index in 1...2 {
            star.coordinators[index].join(roomID: "room", nickname: "Joiner")
            star.flush()
        }
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        host.confirmRoomCode(generation: host.engine.generation)
        star.flush()
        XCTAssertNil(host.submitFigure("12", generation: host.engine.generation))
        star.flush()
        XCTAssertEqual(host.engine.phase, .confirming, "the joiners never confirmed")
        host.leave()
        let report = Diagnostics.report(for: host, appVersion: "0.1", build: "1",
                                        systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("own share: not sent"), report)
    }

    /// The summary goes into the same support email, so it obeys the same rule as the rest.
    func testTheLastRoundCarriesNoRoundContent() async {
        let star = await roundInProgress()
        let engine = star.coordinators[0].engine
        let code = engine.roomCode!.code
        let hash = engine.roster!.rosterHash.base64EncodedString()
        star.coordinators[0].leave()
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("last round:"), report)
        for secret in ["Zebediah", "Wilhelmina", "Bartholomew", "Quarterly bonus review",
                       "98765", code, hash] {
            XCTAssertFalse(report.contains(secret), "the report leaked \(secret.debugDescription):\n\(report)")
        }
    }

    /// Each connection's counts are what tell the three explanations apart: a send that never
    /// finished, a host that stopped reading, or a link that went quiet.
    func testTheLastRoundListsEachConnection() async {
        let star = await roundInProgress()
        star.transports[0].linkLog = LinkLog([
            LinkReport(toHost: false, end: .open, route: .peerToPeer, routeChanges: 1, timesUnusable: 2,
                       secondsOpen: 95, framesSent: 12, framesReceived: 4,
                       waitingToSend: 3, secondsSending: 61, secondsSinceLastReceived: 70),
            LinkReport(toHost: false, end: .lost, route: .wifiNetwork, secondsOpen: 30, framesSent: 9, framesReceived: 6,
                       waitingToSend: 0, secondsSending: nil, secondsSinceLastReceived: nil),
            LinkReport(toHost: true, end: .closedThere, secondsOpen: 0),
            LinkReport(toHost: true, end: .leftRoom, route: .other),
        ])
        star.coordinators[0].leave()
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains(
            "link 1 to a joiner: open, via peer-to-peer Wi-Fi, route changed 1 times, unusable 2 times, 95 s, sent 12, received 4, waiting to send 3, sending for 61 s, quiet for 70 s"),
            report)
        XCTAssertTrue(report.contains(
            "link 2 to a joiner: lost, via a Wi-Fi network, 30 s, sent 9, received 6, waiting to send 0, nothing received"),
            report)
        XCTAssertTrue(report.contains("link 3 to the host: closed by the other phone, route unknown, 0 s,"), report)
        XCTAssertTrue(report.contains("link 4 to the host: closed on leaving, via another route,"), report)
    }

    /// Device report 2026-10-11: the summary was taken before Leave queued the host's abort, so every
    /// joiner had received one frame more than the host's report said it sent. The links are read
    /// when the report is made, after leaving has sent what it queued.
    func testTheLastRoundCountsWhatLeavingSent() async {
        let star = await roundInProgress()
        let sentBefore = star.transports[0].sentCount
        star.coordinators[0].leave()
        let sentAfter = star.transports[0].sentCount
        XCTAssertGreaterThan(sentAfter, sentBefore, "the host's leave sends an abort")
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("link 1 to a joiner: open, route unknown, 0 s, sent \(sentAfter),"), report)
    }

    /// Device report 2026-10-11: when this phone's figure completed the set, the engine passed through
    /// sharing within one step and the report said the share was never sent.
    func testAShareThatCompletesTheSetIsReportedAsSent() async {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Lunch", size: 3, nickname: "Host")
        for index in 1...2 {
            star.coordinators[index].join(roomID: "room", nickname: "Joiner")
            star.flush()
        }
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        for coordinator in star.coordinators {
            coordinator.confirmRoomCode(generation: coordinator.engine.generation)
        }
        star.flush()
        for joiner in star.coordinators.dropFirst() {
            XCTAssertNil(joiner.submitFigure("5", generation: joiner.engine.generation))
        }
        star.flush()
        star.clock.now += 3_000
        XCTAssertNil(host.submitFigure("7", generation: host.engine.generation))
        XCTAssertNotEqual(host.engine.phase, .sharing, "the host's share was the last one in")
        host.leave()
        let report = Diagnostics.report(for: host, appVersion: "0.1", build: "1",
                                        systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("own share sent after: 3 s"), report)
    }

    /// Since-launch failures cannot say which round they belong to; the summary counts its own.
    func testTheLastRoundCountsOnlyItsOwnSendFailures() async {
        let star = await roundInProgress(sendFailuresBefore: 4)
        star.transports[0].sendFailures += 5
        star.coordinators[0].leave()
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        let parts = report.components(separatedBy: "last round:")
        XCTAssertEqual(parts.count, 2, report)
        XCTAssertTrue(parts[0].contains("send failures: 9"), "the since-launch line stays:\n\(report)")
        XCTAssertTrue(parts[1].contains("send failures: 5"), "only this room's failures:\n\(report)")
    }

    func testAnIdleAppStillProducesAReport() {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("idle"))
        XCTAssertFalse(report.isEmpty)
    }
}
