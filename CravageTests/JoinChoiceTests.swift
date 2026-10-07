import XCTest
import CravageCore
@testable import Cravage

/// Join, option B (decided 2026-10-04): pick a room, then join it with one clear button.
final class JoinChoiceTests: XCTestCase {
    private func room(_ id: String, _ label: String, host: String = "Sam") -> RoomAdvert {
        RoomAdvert(id: id, label: label, size: 4, hostNickname: host, protocolVersion: CravageCore.protocolVersion)
    }

    func testNothingIsChosenUntilARoomIsPicked() {
        XCTAssertNil(JoinChoice.chosen(nil, in: [room("a", "Annual bonus")]))
        XCTAssertEqual(JoinChoice.chosen("a", in: [room("a", "Annual bonus")])?.label, "Annual bonus")
    }

    /// A room that stops advertising (the host closed it, or started the round) cannot stay chosen,
    /// so the button never joins a room that is no longer there.
    func testAChosenRoomThatDisappearsIsNoLongerChosen() {
        XCTAssertNil(JoinChoice.chosen("a", in: [room("b", "Day rate")]))
        XCTAssertNil(JoinChoice.chosen("a", in: []))
    }

    func testTheButtonNamesTheRoomOrAsksForOne() {
        XCTAssertEqual(JoinChoice.buttonTitle(for: room("a", "Annual bonus")), "Join Annual bonus")
        XCTAssertEqual(JoinChoice.buttonTitle(for: nil), "Pick a room to join")
    }

    /// The note may say a room code is compared before the figure is asked for, which is the
    /// confirmation barrier; it may not claim nothing is sent, since joining sends the nickname.
    func testTheNoteNamesTheHostAndClaimsOnlyWhatIsTrue() throws {
        let note = try XCTUnwrap(JoinChoice.note(for: room("a", "Annual bonus", host: "Priya")))
        XCTAssertEqual(note, "Hosted by Priya. Everyone compares a room code before your figure is asked for.")
        for claim in ["nothing is sent", "anything is sent", "nothing leaves"] {
            XCTAssertFalse(note.lowercased().contains(claim), note)
        }
        XCTAssertNil(JoinChoice.note(for: nil))
    }
}
