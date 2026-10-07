import Foundation
import Observation

/// The unlock for rooms of 4 to 8 people (delivery step 8; PLAN.md "Purchase"). One non-consumable,
/// bought by the host for their Apple ID; Family Sharing is off in the product's configuration.
///
/// The answer the coordinator acts on comes from `hasVerifiedUnlock()`, which re-reads what the
/// store says this Apple ID holds every time a room is opened; the engine then enforces it (SPEC
/// invariant 11). `unlocked` is that answer cached for drawing padlocks, never a permission.
@MainActor
@Observable
final class StoreManager: EntitlementProvider {
    nonisolated static let unlockProductID = "com.dylanliew.cravage.unlock"

    enum Problem: Equatable {
        /// The store returned a purchase whose signature did not check out.
        case unverified
        case purchaseFailed
        case restoreFailed
    }

    enum Status: Equatable {
        case idle
        case working
        /// Waiting for approval; the unlock arrives on its own if it is given.
        case pending
        case nothingToRestore
        /// The store confirmed a verified purchase of the unlock, but its list of what this Apple ID
        /// owns does not show it yet. Not called a failure: money may have changed hands.
        case recordedNotShown
        case failed(Problem)
    }

    private(set) var unlocked = false
    /// The App Store's localized price, shown exactly as given. Nil until loaded or if it cannot be.
    private(set) var price: String?
    private(set) var status: Status = .idle

    @ObservationIgnored private let backend: StoreBackend
    @ObservationIgnored private var listener: Task<Void, Never>?
    /// Reads of what is owned can overlap; only the newest one started may set `unlocked`.
    @ObservationIgnored private var readsStarted = 0

    init(backend: StoreBackend) {
        self.backend = backend
    }

    /// At launch: listen for transactions first (Apple delivers unfinished ones once, right after
    /// launch), then read what is already owned and the price. Never restores on its own.
    func start() {
        guard listener == nil else { return }
        let updates = backend.updates()
        listener = Task { [weak self] in
            for await _ in updates {
                await self?.updateArrived()
            }
        }
        Task {
            _ = await hasVerifiedUnlock()
            await loadPrice()
        }
    }

    func loadPrice() async {
        price = (try? await backend.displayPrice(for: Self.unlockProductID)) ?? nil
    }

    func hasVerifiedUnlock() async -> Bool {
        readsStarted += 1
        let read = readsStarted
        let owned = await backend.currentEntitlements()
        let answer = owned.contains { Self.counts($0) }
        if read == readsStarted { unlocked = answer }
        return answer
    }

    private static func counts(_ record: UnlockRecord) -> Bool {
        record.productID == unlockProductID && record.verified && !record.revoked
    }

    func buy() async {
        guard status != .working else { return }
        status = .working
        do {
            switch try await backend.purchase(Self.unlockProductID) {
            case let .purchased(record):
                if await hasVerifiedUnlock() {
                    status = .idle
                } else if Self.counts(record) {
                    status = .recordedNotShown
                } else if record.productID == Self.unlockProductID && !record.verified {
                    status = .failed(.unverified)
                } else {
                    status = .failed(.purchaseFailed)
                }
            case .pending:
                status = .pending
            case .cancelled:
                status = .idle
            }
        } catch {
            status = .failed(.purchaseFailed)
        }
    }

    /// Only ever called from the Restore button: it can show an App Store sign-in prompt.
    func restore() async {
        guard status != .working else { return }
        status = .working
        do {
            try await backend.sync()
            status = await hasVerifiedUnlock() ? .idle : .nothingToRestore
        } catch {
            status = .failed(.restoreFailed)
        }
    }

    /// Approvals, purchases on another device, refunds and revocations all land here. The store's
    /// list of what is owned is re-read rather than trusting the single record. An unlock that
    /// arrives clears whatever note was showing, unless a buy or restore is running.
    private func updateArrived() async {
        let owned = await hasVerifiedUnlock()
        if owned, status != .working { status = .idle }
    }
}
