import XCTest
@testable import CravageCore
@testable import Cravage

final class OutcomeCopyTests: XCTestCase {
    private let a = PartyLabel.all[0]
    private let b = PartyLabel.all[1]
    private func name(_ label: PartyLabel) -> String {
        label == a ? "Alex" : "Dee"
    }

    /// SPEC: the transcript has no way to say a result was disputed, so only a round this phone saw
    /// agreed is ever written out.
    func testOnlyAnAgreedRoundCanBeExported() {
        XCTAssertTrue(OutcomeCopy.canExport(.agreed))
        XCTAssertFalse(OutcomeCopy.canExport(.disputed(a)))
        XCTAssertFalse(OutcomeCopy.canExport(.partial(missing: [a])))
        XCTAssertFalse(OutcomeCopy.canExport(.mismatch([a])))
    }

    func testAMismatchShowsNoAverage() {
        XCTAssertFalse(OutcomeCopy.showsAverage(.mismatch([a])))
        XCTAssertTrue(OutcomeCopy.showsAverage(.agreed))
        XCTAssertTrue(OutcomeCopy.showsAverage(.partial(missing: [a])),
                      "a partial round still shows the number, marked not agreed")
    }

    /// A relay can make two honest phones each name the other, so the wording never accuses.
    func testTheMismatchWordingNeverAccusesAnyone() {
        let text = OutcomeCopy.detail(.mismatch([a]), size: 3, name: name)
        XCTAssertEqual(text, "Alex's phone did not agree with this phone about the shares. "
                       + "This does not mean Alex did anything wrong. No average is shown.")
    }

    func testAgreementNamesTheWholeRoom() {
        XCTAssertEqual(OutcomeCopy.detail(.agreed, size: 3, name: name),
                       "All 3 phones signed agreement to the same set of shares.")
    }

    func testSeveralPhonesReadAsAList() {
        let text = OutcomeCopy.detail(.partial(missing: [a, b]), size: 3, name: name)
        XCTAssertTrue(text.hasPrefix("Alex's and Dee's phones didn't sign agreement in time."), text)
    }
}
