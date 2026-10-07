import Foundation
import StoreKit
import UIKit

/// The real store, and the only file that imports StoreKit. StoreKit's Swift interface carries no
/// doc comments; the behaviour relied on here is from Apple's StoreKit documentation pages
/// (read 2026-10-03): `Transaction.currentEntitlements` lists each non-consumable and leaves out
/// refunded or revoked ones; `Transaction.updates` should be listened to from launch and also
/// carries revocations; `AppStore.sync()` shows a sign-in prompt and belongs only behind a button.
@MainActor
final class StoreKitBackend: StoreBackend {
    func displayPrice(for productID: String) async throws -> String? {
        try await Product.products(for: [productID]).first?.displayPrice
    }

    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [productID]).first else {
            throw StoreKitError.notAvailableInStorefront
        }
        // Apple's purchase(options:) page points UIKit apps at purchase(confirmIn:), which shows
        // the confirmation over the given scene.
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        let result = if let scene { try await product.purchase(confirmIn: scene) } else { try await product.purchase() }
        switch result {
        case let .success(result):
            return .purchased(await record(result, finish: true))
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func currentEntitlements() async -> [UnlockRecord] {
        var records: [UnlockRecord] = []
        for await result in Transaction.currentEntitlements {
            records.append(await record(result, finish: false))
        }
        return records
    }

    func updates() -> AsyncStream<UnlockRecord> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                for await result in Transaction.updates {
                    guard let self else { break }
                    continuation.yield(await self.record(result, finish: true))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    /// A verified transaction from a purchase or an update is finished once read: the unlock is read
    /// back from the store's own list of what is owned, so finishing only stops the store
    /// delivering it again. An unverified one is never finished and never counts.
    private func record(_ result: VerificationResult<Transaction>, finish: Bool) async -> UnlockRecord {
        switch result {
        case let .verified(transaction):
            if finish { await transaction.finish() }
            return UnlockRecord(productID: transaction.productID, verified: true,
                                revoked: transaction.revocationDate != nil)
        case let .unverified(transaction, _):
            // Deliberately left unfinished: the store redelivers it at the next launch, by which
            // time it may verify; finishing it would drop the chance.
            return UnlockRecord(productID: transaction.productID, verified: false,
                                revoked: transaction.revocationDate != nil)
        }
    }
}
