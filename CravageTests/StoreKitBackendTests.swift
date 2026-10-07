import XCTest
import StoreKit
import StoreKitTest
@testable import Cravage

/// The real StoreKit code against Xcode's local store, configured by `Config/Cravage.storekit`
/// (delivery step 8: "local StoreKit tests"). The App Store sandbox comes once enrolment clears.
///
/// Skipped, not passed, when the local store will not serve this build. On this Mac
/// (Xcode 26, iOS 26.5 simulator, 2026-10-03) storekitd refuses every command-line test run with
/// "com.dylanliew.cravage is not installed for development", signed or not; the unlock rules are
/// covered by StoreManagerTests with a fake store, and this file still has to be run from Xcode.
/// CI skips this file by name: on GitHub's runners (Xcode 26.6, 2026-10-07) the store serves the
/// product but the first purchase never returns.
@MainActor
final class StoreKitBackendTests: XCTestCase {
    private var session: SKTestSession!
    private let unlock = StoreManager.unlockProductID

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Cravage", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let served = (try? await Product.products(for: [unlock])) ?? []
        guard !served.isEmpty else {
            throw XCTSkip("Xcode's local StoreKit test store is not serving this build; run these from Xcode")
        }
    }

    override func tearDown() async throws {
        session?.clearTransactions()
    }

    func testThePriceIsTheStoresLocalizedOne() async throws {
        let price = try await StoreKitBackend().displayPrice(for: unlock)
        XCTAssertTrue(price?.contains("0.99") ?? false, String(describing: price))
    }

    func testABuyIsVerifiedAndOwnedUntilItIsRefunded() async throws {
        let backend = StoreKitBackend()
        let outcome = try await backend.purchase(unlock)
        XCTAssertEqual(outcome, .purchased(UnlockRecord(productID: unlock, verified: true, revoked: false)))
        var owned = await backend.currentEntitlements()
        XCTAssertTrue(owned.contains(UnlockRecord(productID: unlock, verified: true, revoked: false)), "\(owned)")

        let transaction = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == unlock })
        try session.refundTransaction(identifier: transaction.identifier)
        owned = await backend.currentEntitlements()
        XCTAssertFalse(owned.contains { $0.productID == self.unlock && $0.verified && !$0.revoked },
                       "a refunded unlock no longer counts: \(owned)")
    }

    func testAskToBuyIsPendingAndUnlocksNothing() async throws {
        session.askToBuyEnabled = true
        let backend = StoreKitBackend()
        let outcome = try await backend.purchase(unlock)
        XCTAssertEqual(outcome, .pending)
        let owned = await backend.currentEntitlements()
        XCTAssertFalse(owned.contains { $0.productID == self.unlock })
    }

    func testTheStoreManagerSeesAnEarlierPurchaseAtLaunch() async throws {
        _ = try await session.buyProduct(identifier: unlock)
        let store = StoreManager(backend: StoreKitBackend())
        let unlocked = await store.hasVerifiedUnlock()
        XCTAssertTrue(unlocked)
    }
}
