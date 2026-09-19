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

    /// CLAUDE.md forbids "nothing is sent"; what is true is that the share that goes is masked.
    func testTheLostConnectionLineClaimsOnlyWhatIsTrue() {
        let text = FailureCopy.detail(.connectionLost, name: name)
        XCTAssertEqual(text, "The round has stopped. Nothing you entered was sent unmasked.")
        XCTAssertFalse(text.contains("nothing was sent"))
    }

    func testEveryStageTimeoutSaysWhatWasBeingWaitedFor() {
        let stages: [Stage] = [.lobby, .confirming, .keyExchange, .sharing, .collectingConfirmations]
        for stage in stages {
            let text = FailureCopy.detail(.timeout(stage), name: name)
            XCTAssertFalse(text.hasPrefix("The round has stopped"),
                           "stage \(stage) fell through to the generic line")
            XCTAssertTrue(text.contains("in time."), text)
        }
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
