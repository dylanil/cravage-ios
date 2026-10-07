import XCTest
@testable import Cravage

final class UnlockCopyTests: XCTestCase {
    /// The price is the App Store's own string, never one written into the app (PLAN.md step 4).
    func testTheButtonShowsTheStoresPriceAndWaitsForIt() {
        XCTAssertEqual(UnlockCopy.buyTitle(price: "£0.99"), "Unlock for £0.99")
        XCTAssertEqual(UnlockCopy.buyTitle(price: "0,99 €"), "Unlock for 0,99 €")
        XCTAssertNil(UnlockCopy.buyTitle(price: nil), "no price, no button that pretends to know one")
    }

    func testEveryOutcomeSaysWhatHappenedWithoutClaimingMore() {
        let all: [StoreManager.Status] = [.pending, .nothingToRestore, .recordedNotShown, .failed(.unverified),
                                          .failed(.purchaseFailed), .failed(.restoreFailed)]
        for status in all {
            let text = UnlockCopy.note(status)
            XCTAssertNotNil(text, "\(status)")
            for claim in ["charged", "refund", "forever", "lifetime"] {
                XCTAssertFalse(text!.lowercased().contains(claim), "\(status): \(text!)")
            }
        }
        XCTAssertNil(UnlockCopy.note(.idle))
        XCTAssertNil(UnlockCopy.note(.working))
    }

    /// Family Sharing is off, so the unlock belongs to the Apple ID that bought it, and only the
    /// host needs it.
    func testTheOfferSaysWhoPaysAndWhoOwnsIt() {
        XCTAssertTrue(UnlockCopy.offer.contains("Apple ID"))
        XCTAssertTrue(UnlockCopy.offer.contains("joining"))
    }

    /// Review finding 7: the refusal must not point at a button that may not be there.
    func testThePriceMissingLineOffersARetry() {
        XCTAssertEqual(UnlockCopy.retryPrice, "Try loading the price again")
    }
}
