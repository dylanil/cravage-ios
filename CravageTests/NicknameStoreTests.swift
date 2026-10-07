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
        for bad in ["", "   ", "\u{202E}Dee", "Dee\nAlex", String(repeating: "D", count: 49), "De\u{200B}e", "\u{2764}\u{FE0F}"] {
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

    /// Foundation's trimming counts a zero-width space as whitespace, so one at either end is
    /// removed rather than refused. What is saved is still a name the roster accepts.
    func testAnInvisibleCharacterAtEitherEndIsTrimmedNotSaved() {
        let store = NicknameStore(defaults: defaults)
        XCTAssertTrue(store.save("\u{200B}Dee\u{200B}"))
        XCTAssertEqual(store.nickname, "Dee")
        XCTAssertTrue(RoomText.isValidNickname(store.nickname))
    }

    func testAStoredNameThatIsNoLongerValidIsIgnoredOnOpening() {
        defaults.set("Dee\u{2028}Alex", forKey: "nickname")
        XCTAssertEqual(NicknameStore(defaults: defaults).nickname, "")
        // A name saved before invisible characters were refused (2026-09-24) is asked for again.
        defaults.set("De\u{200B}e", forKey: "nickname")
        XCTAssertEqual(NicknameStore(defaults: defaults).nickname, "")
    }
}
