import XCTest
@testable import CravageCore
@testable import Cravage

final class NewRoomFormTests: XCTestCase {

    /// Three people is the free room; every larger one carries a padlock until the store says this
    /// Apple ID holds the unlock.
    func testOnlyTheFreeRoomIsUnlockedUntilTheStoreSaysOtherwise() {
        var form = NewRoomForm()
        XCTAssertFalse(form.isLocked(3))
        for size in 4...8 {
            XCTAssertTrue(form.isLocked(size), "room for \(size) should be locked")
        }

        form.unlocked = true
        for size in NewRoomForm.sizes {
            XCTAssertFalse(form.isLocked(size), "room for \(size) should be open once unlocked")
        }
    }

    func testTheOfferedSizesAreTheOnesARosterCanHold() {
        XCTAssertEqual(NewRoomForm.sizes, [3, 4, 5, 6, 7, 8])
    }

    func testALabelTheRosterWouldRejectCannotOpenARoom() {
        var form = NewRoomForm()
        for bad in ["", "   ", "Bonus\nround", "\u{202E}Bonus", String(repeating: "x", count: 121), "Bon\u{200B}us",
                    "Bonus \u{2764}\u{FE0F}"] {
            form.label = bad
            XCTAssertFalse(form.canOpen, "opened on a label the roster rejects: \(bad.debugDescription)")
        }

        form.label = "  Annual bonus  "
        XCTAssertTrue(form.canOpen)
        XCTAssertEqual(form.trimmedLabel, "Annual bonus")
    }

    /// A refused label says why, instead of leaving a greyed-out button to guess at. An empty
    /// field is not a problem to report: the person has not typed anything yet.
    func testARefusedLabelSaysWhy() {
        var form = NewRoomForm()
        XCTAssertNil(form.labelProblem)
        form.label = "Bonus \u{2764}\u{FE0F}"
        XCTAssertNotNil(form.labelProblem)
        form.label = "Bonus"
        XCTAssertNil(form.labelProblem)
    }
}
