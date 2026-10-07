import XCTest
@testable import Cravage

/// A store whose answers each test sets: what a purchase returns, what the phone currently owns,
/// and what arrives later on the updates stream.
@MainActor
final class FakeStoreBackend: StoreBackend {
    var price: String? = "£0.99"
    var priceFails = false
    var outcome: Result<PurchaseOutcome, Error> = .success(.cancelled)
    var owned: [UnlockRecord] = []
    var purchases = 0
    var syncs = 0
    var syncFails = false
    var purchaseGate: CheckedContinuation<Void, Never>?
    var holdPurchase = false
    private var continuation: AsyncStream<UnlockRecord>.Continuation?

    struct Failure: Error {}

    func displayPrice(for productID: String) async throws -> String? {
        if priceFails { throw Failure() }
        return productID == StoreManager.unlockProductID ? price : nil
    }

    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        purchases += 1
        // Only the first purchase waits, so a second one (a missing double-tap guard) is counted, not hung.
        if holdPurchase {
            holdPurchase = false
            await withCheckedContinuation { purchaseGate = $0 }
        }
        return try outcome.get()
    }

    /// Reads wait here while `holdReads` is set, so a test can make an older read finish last.
    var holdReads = false
    var readGates: [CheckedContinuation<Void, Never>] = []

    func currentEntitlements() async -> [UnlockRecord] {
        let answer = owned
        if holdReads { await withCheckedContinuation { readGates.append($0) } }
        return answer
    }

    var updateStreams = 0

    func updates() -> AsyncStream<UnlockRecord> {
        updateStreams += 1
        return AsyncStream { continuation = $0 }
    }

    func sync() async throws {
        syncs += 1
        if syncFails { throw Failure() }
    }

    func send(_ record: UnlockRecord) { continuation?.yield(record) }
}

@MainActor
final class StoreManagerTests: XCTestCase {
    private let unlock = StoreManager.unlockProductID
    private var verified: UnlockRecord { UnlockRecord(productID: unlock, verified: true, revoked: false) }

    private func manager(_ backend: FakeStoreBackend) async -> StoreManager {
        let manager = StoreManager(backend: backend)
        manager.start()
        await settle()
        return manager
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: - What counts as unlocked

    func testOnlyAVerifiedUnrevokedUnlockForThisProductCounts() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        for owned in [[UnlockRecord(productID: unlock, verified: false, revoked: false)],
                      [UnlockRecord(productID: unlock, verified: true, revoked: true)],
                      [UnlockRecord(productID: "com.example.other", verified: true, revoked: false)],
                      []] {
            backend.owned = owned
            let answer = await store.hasVerifiedUnlock()
            XCTAssertFalse(answer, "\(owned)")
            XCTAssertFalse(store.unlocked)
        }
        backend.owned = [verified]
        let answer = await store.hasVerifiedUnlock()
        XCTAssertTrue(answer)
        XCTAssertTrue(store.unlocked)
    }

    /// The plan's "offline cold start with purchase": an earlier purchase unlocks from what the
    /// phone already holds, even when the price cannot be fetched.
    func testAnEarlierPurchaseUnlocksAtStartWithoutBuyingOrAPrice() async {
        let backend = FakeStoreBackend()
        backend.priceFails = true
        backend.owned = [verified]
        let store = await manager(backend)
        XCTAssertTrue(store.unlocked)
        XCTAssertNil(store.price)
        XCTAssertEqual(backend.purchases, 0)
        XCTAssertEqual(backend.syncs, 0, "restore can show a sign-in prompt, so it is never automatic")
    }

    func testThePriceIsTheStoresOwnLocalizedString() async {
        let backend = FakeStoreBackend()
        backend.price = "0,99 €"
        let store = await manager(backend)
        XCTAssertEqual(store.price, "0,99 €")
    }

    // MARK: - Buying

    func testAVerifiedPurchaseUnlocks() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.outcome = .success(.purchased(verified))
        backend.owned = [verified]
        await store.buy()
        XCTAssertTrue(store.unlocked)
        XCTAssertEqual(store.status, .idle)
    }

    func testAnUnverifiedPurchaseDoesNotUnlockAndSaysSo() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        let unverified = UnlockRecord(productID: unlock, verified: false, revoked: false)
        backend.outcome = .success(.purchased(unverified))
        backend.owned = [unverified]
        await store.buy()
        XCTAssertFalse(store.unlocked)
        XCTAssertEqual(store.status, .failed(.unverified))
    }

    func testCancellingChangesNothing() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.outcome = .success(.cancelled)
        await store.buy()
        XCTAssertFalse(store.unlocked)
        XCTAssertEqual(store.status, .idle)
    }

    func testAFailedPurchaseSaysSoWithoutUnlocking() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.outcome = .failure(FakeStoreBackend.Failure())
        await store.buy()
        XCTAssertFalse(store.unlocked)
        XCTAssertEqual(store.status, .failed(.purchaseFailed))
    }

    /// Ask to Buy: the purchase waits for approval and arrives later on the updates stream.
    func testAPendingPurchaseUnlocksWhenItIsApprovedLater() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.outcome = .success(.pending)
        await store.buy()
        XCTAssertEqual(store.status, .pending)
        XCTAssertFalse(store.unlocked)
        backend.owned = [verified]
        backend.send(verified)
        await settle()
        XCTAssertTrue(store.unlocked)
        XCTAssertEqual(store.status, .idle)
    }

    func testADoubleTapOnUnlockIsOnePurchase() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.holdPurchase = true
        backend.outcome = .success(.purchased(verified))
        backend.owned = [verified]
        let first = Task { await store.buy() }
        await settle()
        await store.buy()
        XCTAssertEqual(backend.purchases, 1)
        backend.purchaseGate?.resume()
        await first.value
        XCTAssertTrue(store.unlocked)
    }

    // MARK: - Updates arriving on their own

    func testRepeatedUpdatesChangeNothingTheSecondTime() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.owned = [verified]
        backend.send(verified)
        backend.send(verified)
        await settle()
        XCTAssertTrue(store.unlocked)
        XCTAssertEqual(store.status, .idle)
    }

    func testARefundOrRevocationLocksAgain() async {
        let backend = FakeStoreBackend()
        backend.owned = [verified]
        let store = await manager(backend)
        XCTAssertTrue(store.unlocked)
        backend.owned = []
        backend.send(UnlockRecord(productID: unlock, verified: true, revoked: true))
        await settle()
        XCTAssertFalse(store.unlocked)
    }

    // MARK: - Restore

    func testRestoreFindsAnEarlierPurchase() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.owned = [verified]
        await store.restore()
        XCTAssertEqual(backend.syncs, 1)
        XCTAssertTrue(store.unlocked)
        XCTAssertEqual(store.status, .idle)
    }

    func testRestoreWithNothingToRestoreSaysSo() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        await store.restore()
        XCTAssertFalse(store.unlocked)
        XCTAssertEqual(store.status, .nothingToRestore)
    }

    func testAFailedRestoreSaysSo() async {
        let backend = FakeStoreBackend()
        backend.syncFails = true
        let store = await manager(backend)
        await store.restore()
        XCTAssertEqual(store.status, .failed(.restoreFailed))
    }

    // MARK: - Review 2026-10-04

    /// Finding 2: a purchase the store confirmed but has not yet listed must not be called a failure.
    func testAConfirmedPurchaseNotYetListedIsNotCalledAFailure() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.outcome = .success(.purchased(verified))
        backend.owned = []
        await store.buy()
        XCTAssertFalse(store.unlocked)
        XCTAssertEqual(store.status, .recordedNotShown)
        let other = UnlockRecord(productID: "com.example.other", verified: true, revoked: false)
        backend.outcome = .success(.purchased(other))
        await store.buy()
        XCTAssertEqual(store.status, .failed(.purchaseFailed), "a purchase of something else is not this unlock")
    }

    /// Finding 4: an unlock that arrives later clears any earlier note, not only the waiting one.
    func testAnUnlockArrivingLaterClearsAnEarlierProblem() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        let unverified = UnlockRecord(productID: unlock, verified: false, revoked: false)
        backend.outcome = .success(.purchased(unverified))
        await store.buy()
        XCTAssertEqual(store.status, .failed(.unverified))
        backend.owned = [verified]
        backend.send(verified)
        await settle()
        XCTAssertTrue(store.unlocked)
        XCTAssertEqual(store.status, .idle)
    }

    /// Finding 4: a declined Ask to Buy sends nothing, so the person must still be able to try again.
    func testWhileWaitingForApprovalThePersonCanStillBuyOrRestore() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.outcome = .success(.pending)
        await store.buy()
        XCTAssertEqual(store.status, .pending)
        backend.outcome = .success(.cancelled)
        await store.buy()
        XCTAssertEqual(backend.purchases, 2, "waiting does not block another try")
        await store.restore()
        XCTAssertEqual(backend.syncs, 1)
    }

    /// Finding 6: an older read of what is owned that finishes last must not overwrite a newer one.
    func testAnOlderReadNeverOverwritesANewerAnswer() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.owned = [verified]
        backend.holdReads = true
        let older = Task { await store.hasVerifiedUnlock() }
        await settle()
        backend.owned = []
        let newer = Task { await store.hasVerifiedUnlock() }
        await settle()
        backend.holdReads = false
        backend.readGates[1].resume()
        _ = await newer.value
        backend.readGates[0].resume()
        _ = await older.value
        XCTAssertFalse(store.unlocked, "the refund read later wins over the earlier read")
    }

    /// Finding 8: updates for another product or with a bad signature unlock nothing.
    func testUpdatesForAnotherProductOrUnverifiedUnlockNothing() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        backend.owned = [UnlockRecord(productID: "com.example.other", verified: true, revoked: false),
                         UnlockRecord(productID: unlock, verified: false, revoked: false)]
        backend.send(backend.owned[0])
        backend.send(backend.owned[1])
        await settle()
        XCTAssertFalse(store.unlocked)
    }

    func testStartingTwiceListensOnce() async {
        let backend = FakeStoreBackend()
        let store = await manager(backend)
        store.start()
        await settle()
        backend.owned = [verified]
        backend.send(verified)
        await settle()
        XCTAssertTrue(store.unlocked)
        XCTAssertEqual(backend.updateStreams, 1)
    }
}
