import XCTest
@testable import CravageCore
@testable import Cravage

/// CLAUDE.md: figures, keys, masks, names and labels never appear in logs, diagnostics or crash
/// annotations. The report is meant to be pasted into a support email by someone who cannot read
/// it, so this is the one test that has to hold whatever else changes.
@MainActor
final class DiagnosticsTests: XCTestCase {

    private func roundInProgress() async -> FakeStar {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        let host = star.coordinators[0]
        await host.createRoom(label: "Partner salary review", size: 3, nickname: "Zebediah")
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

        for secret in ["Zebediah", "Wilhelmina", "Bartholomew", "Partner salary review",
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

        let code = engine.roster!.fingerprint.code
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

    func testAnIdleAppStillProducesAReport() {
        let star = FakeStar(phones: 1, entitlement: FakeEntitlement(unlocked: false))
        let report = Diagnostics.report(for: star.coordinators[0], appVersion: "0.1",
                                        build: "1", systemVersion: "26.6", model: "iPhone17,1")
        XCTAssertTrue(report.contains("idle"))
        XCTAssertFalse(report.isEmpty)
    }
}
