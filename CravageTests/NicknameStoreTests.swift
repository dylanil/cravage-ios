import XCTest
@testable import CravageCore
@testable import Cravage

@MainActor
final class NicknameStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "nickname-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// The roster rejects these, so accepting them here would only fail later at the point of
    /// joining a room.
    func testANameTheRosterWouldRejectIsNeverSaved() {
        let store = NicknameStore(defaults: defaults)
        for bad in ["", "   ", "\u{202E}Dee", "Dee\nAlex", String(repeating: "D", count: 49)] {
            XCTAssertFalse(store.save(bad), "saved a name the roster rejects: \(bad.debugDescription)")
        }
        XCTAssertEqual(store.nickname, "")
        XCTAssertFalse(store.hasNickname)
    }

    func testAGoodNameIsKeptOnThisPhone() {
        let store = NicknameStore(defaults: defaults)
        XCTAssertTrue(store.save("  Dee  "), "surrounding spaces are trimmed, not rejected")
        XCTAssertEqual(store.nickname, "Dee")

        let reopened = NicknameStore(defaults: defaults)
        XCTAssertEqual(reopened.nickname, "Dee")
        XCTAssertTrue(reopened.hasNickname)
    }

    func testAStoredNameThatIsNoLongerValidIsIgnoredOnOpening() {
        defaults.set("Dee\u{2028}Alex", forKey: "nickname")
        XCTAssertEqual(NicknameStore(defaults: defaults).nickname, "")
    }
}
