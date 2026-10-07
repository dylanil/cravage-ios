import XCTest
@testable import CravageCore
@testable import Cravage

final class FailureCopyTests: XCTestCase {
    private let a = PartyLabel.all[0]
    private func name(_ label: PartyLabel) -> String { "Alex" }

    /// A relay, or a phone that simply dropped, can produce this. The wording never accuses.
    func testConflictingMessagesAreNotWrittenAsAnAccusation() {
        let text = FailureCopy.detail(.conflictingMessage(a), name: name)
        XCTAssertTrue(text.contains("This does not mean Alex did anything wrong."), text)
    }

    /// CONTRIBUTING.md forbids "nothing is sent"; what is true is that the share that goes is masked.
    /// A value that does not open its seal can come from a host showing phones different rooms, so
    /// it is not written as the named phone's fault.
    func testARevealMismatchIsNotWrittenAsAnAccusation() {
        let text = FailureCopy.detail(.revealMismatch(a), name: name)
        XCTAssertTrue(text.contains("does not mean"), text)
        XCTAssertEqual(FailureCopy.title(.revealMismatch(a)), "The phones could not agree a room code")
    }

    /// "The codes don't match" ends the round with a reason, not a silent exit (decided 2026-10-03).
    func testCodesThatDifferSayWhatThatMeans() {
        XCTAssertEqual(FailureCopy.title(.codesDiffered), "The codes didn't match")
        let text = FailureCopy.detail(.codesDiffered, name: name)
        XCTAssertTrue(text.contains("same code"), text)
        XCTAssertFalse(text.lowercased().contains("nothing was sent"))
    }

    /// Before 2026-10-04 the others saw only "a phone left". Now they see whose phone disagreed,
    /// without blame: a misread and a second room look the same from here.
    func testOtherPhonesSeeWhoseCodeDiffered() {
        XCTAssertEqual(FailureCopy.title(.codeDisputed(a)), "The codes didn't match")
        let text = FailureCopy.detail(.codeDisputed(a), name: name)
        XCTAssertTrue(text.hasPrefix("Alex's phone showed a different room code"), text)
        XCTAssertTrue(text.contains("same code"), text)
        XCTAssertTrue(text.contains("This does not mean Alex did anything wrong."), text)
        XCTAssertFalse(text.lowercased().contains("nothing was sent"))
    }

    func testTheLostConnectionLineClaimsOnlyWhatIsTrue() {
        let text = FailureCopy.detail(.connectionLost, name: name)
        XCTAssertEqual(text, "The round has stopped. Nothing you entered was sent unmasked.")
        XCTAssertFalse(text.contains("nothing was sent"))
    }

    func testEveryStageTimeoutSaysWhatWasBeingWaitedFor() {
        let stages: [Stage] = [.lobby, .revealing, .confirming, .keyExchange, .sharing, .collectingConfirmations]
        for stage in stages {
            let text = FailureCopy.detail(.timeout(stage), name: name)
            XCTAssertFalse(text.hasPrefix("The round has stopped"),
                           "stage \(stage) fell through to the generic line")
            XCTAssertTrue(text.contains("in time."), text)
        }
    }

    /// Review 2026-10-07, finding 3: with the full-room rule, a lobby usually times out with most
    /// people in, so the line cannot say nobody joined.
    func testALobbyTimeoutDoesNotSayNobodyJoined() {
        XCTAssertTrue(FailureCopy.detail(.timeout(.lobby), name: name).hasPrefix("Not everyone joined in time."))
    }

    /// `TransportProblem.unavailable` documents an honest generic error with retry; the review
    /// found no screen implementing it, so both cases now have wording and only one has Settings.
    func testEveryTransportProblemHasWordingAndOnlyPermissionOffersSettings() {
        for problem in [TransportProblem.localNetworkDenied, .unavailable] {
            XCTAssertFalse(ProblemCopy.title(problem).isEmpty)
            XCTAssertFalse(ProblemCopy.detail(problem).isEmpty)
        }
        XCTAssertTrue(ProblemCopy.offersSettings(.localNetworkDenied))
        XCTAssertFalse(ProblemCopy.offersSettings(.unavailable),
                       "there is no Settings page that fixes a network that is simply unreachable")
    }

    func testADeclinedJoinerGoesBackToTheRoomList() {
        XCTAssertEqual(FailureCopy.leaveTitle(.declined), "Back to rooms")
        XCTAssertEqual(FailureCopy.leaveTitle(.connectionLost), "Leave room")
        XCTAssertEqual(FailureCopy.title(.declined), "You weren't admitted")
    }
}
