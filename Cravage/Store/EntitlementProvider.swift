import Foundation

/// Answers whether this Apple ID holds a verified unlock for rooms of 4 to 8 people. The
/// coordinator asks at room creation and passes the answer into the engine, which enforces it
/// (SPEC invariant 11). StoreManager implements this in delivery step 8.
@MainActor
protocol EntitlementProvider: AnyObject {
    func hasVerifiedUnlock() async -> Bool
}

/// Until StoreKit lands: nobody is unlocked, so rooms are capped at three people.
@MainActor
final class NoUnlockYet: EntitlementProvider {
    func hasVerifiedUnlock() async -> Bool { false }
}
