import Foundation

/// Answers whether this Apple ID holds a verified unlock for rooms of 4 to 8 people. The
/// coordinator asks at room creation and passes the answer into the engine, which enforces it
/// (SPEC invariant 11). StoreManager is the real one; tests use a fake.
@MainActor
protocol EntitlementProvider: AnyObject {
    func hasVerifiedUnlock() async -> Bool
}
