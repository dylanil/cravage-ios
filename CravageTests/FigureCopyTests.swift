import XCTest
@testable import CravageCore
@testable import Cravage

final class FigureCopyTests: XCTestCase {

    /// The sentence has to follow the room it is shown in, since the protection it describes does.
    func testTheCollusionLineFollowsTheRoomSize() {
        XCTAssertEqual(FigureCopy.collusion(size: 3),
                       "With 3 people, the other 2 could work out your figure if they shared theirs with each other.")
        XCTAssertEqual(FigureCopy.collusion(size: 8),
                       "With 8 people, the other 7 could work out your figure if they shared theirs with each other.")
        XCTAssertEqual(FigureCopy.collusion(size: 2),
                       "With 2 people, the other person could work out your figure.",
                       "with one other party there is nobody to share with")
    }

    /// CLAUDE.md's allowed honesty copy, word for word.
    func testTheOnThisPhoneLineIsTheApprovedWording() {
        XCTAssertEqual(FigureCopy.onThisPhone,
                       "Your figure is processed on your phone; the app sends a masked share to the other participants.")
    }

    /// The screen must not invite a decimal mark the parser rejects, and must say why, because a
    /// comma means opposite things in different countries.
    func testTheLimitLineExplainsWhyACommaIsRefused() {
        XCTAssertTrue(FigureCopy.limit.contains("full stop"))
        XCTAssertTrue(FigureCopy.limit.contains("comma is not accepted"))
        XCTAssertTrue(FigureCopy.limit.contains("separates thousands"))
        XCTAssertThrowsError(try FixedPoint.parseDecimalToFixed("1,5"),
                             "a comma meant as a decimal point is refused, not guessed at")
        XCTAssertThrowsError(try FixedPoint.parseDecimalToFixed("1,500"),
                             "a comma meant as a thousands separator is refused too")
        XCTAssertEqual(try FixedPoint.parseDecimalToFixed("1.5"), 1_500_000)
    }
}
