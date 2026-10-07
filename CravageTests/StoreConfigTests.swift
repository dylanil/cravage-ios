import XCTest
@testable import Cravage

/// Review 2026-10-04, finding 5: the StoreKit tests skip when the local store will not serve
/// this build, which would also hide a broken configuration. This checks the file itself, everywhere.
final class StoreConfigTests: XCTestCase {
    func testTheLocalStoreDefinesTheAgreedUnlock() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Cravage", withExtension: "storekit"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        XCTAssertEqual(products.count, 1)
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product["productID"] as? String, StoreManager.unlockProductID)
        XCTAssertEqual(product["type"] as? String, "NonConsumable")
        XCTAssertEqual(product["familyShareable"] as? Bool, false, "the copy says the unlock is for this Apple ID")
        XCTAssertEqual(product["displayPrice"] as? String, "0.99", "decided: 99p / $0.99")
        let settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertNil(settings["_developerTeamID"], "the team ID stays out of tracked files")
    }
}
