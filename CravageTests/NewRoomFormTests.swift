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
        for bad in ["", "   ", "Bonus\nround", "\u{202E}Bonus", String(repeating: "x", count: 121)] {
            form.label = bad
            XCTAssertFalse(form.canOpen, "opened on a label the roster rejects: \(bad.debugDescription)")
        }

        form.label = "  Annual bonus  "
        XCTAssertTrue(form.canOpen)
        XCTAssertEqual(form.trimmedLabel, "Annual bonus")
    }
}
