import XCTest
@testable import Cravage

/// "Why Cravage?" (decided 2026-10-04): examples avoid pay, and the page ends on what Cravage does
/// not protect rather than leaving the reader with only the case for it.
final class WhyCopyTests: XCTestCase {
    func testExamplesAvoidPay() {
        for item in WhyCopy.items {
            for word in ["salary", "salaries", "bonus", "wage", "pay "] {
                XCTAssertFalse((item.question + " " + item.answer).lowercased().contains(word), "\(item.question): \(word)")
            }
        }
    }

    func testThePageEndsOnWhatItDoesNotProtect() throws {
        let last = try XCTUnwrap(WhyCopy.items.last)
        XCTAssertEqual(last.question, "What doesn't it protect?")
        XCTAssertTrue(last.answer.contains("work out your figure"), "the collusion floor is stated, not argued away")
    }
}
