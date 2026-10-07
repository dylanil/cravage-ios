import Foundation

/// What the store says about one unlock: whether its signature checked out, and whether Apple has
/// since refunded or revoked it. Only a verified, unrevoked record for the unlock product counts.
struct UnlockRecord: Equatable, Sendable {
    let productID: String
    let verified: Bool
    let revoked: Bool
}

enum PurchaseOutcome: Equatable, Sendable {
    case purchased(UnlockRecord)
    /// Waiting for approval (Ask to Buy) or another step; the result arrives on `updates()`.
    case pending
    case cancelled
}

/// The seam between StoreManager and StoreKit, so the unlock rules are tested with a fake store.
/// `StoreKitBackend` is the real one and the only file that imports StoreKit.
@MainActor
protocol StoreBackend: AnyObject {
    /// The App Store's own localized price string, or nil if the product is unknown.
    func displayPrice(for productID: String) async throws -> String?
    func purchase(_ productID: String) async throws -> PurchaseOutcome
    /// Every non-consumable this Apple ID currently holds, as the store reports it.
    func currentEntitlements() async -> [UnlockRecord]
    /// Transactions that happen outside a purchase call: approvals, other devices, refunds.
    func updates() -> AsyncStream<UnlockRecord>
    /// Restore. Shows an App Store sign-in prompt, so it runs only when the person taps Restore.
    func sync() async throws
}
