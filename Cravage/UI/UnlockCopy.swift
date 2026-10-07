import Foundation

/// What the unlock says. Kept apart from the views so
/// the wording rules can be tested: the price is always the App Store's own string, and no line
/// claims anything about money the app cannot see.
enum UnlockCopy {
    static let title = "Rooms for 4 to 8 people"
    static let offer = "A one-off unlock for this Apple ID. The host pays; people joining don't."

    /// Nil until the App Store has given a price: the button is not shown with a guessed one.
    static func buyTitle(price: String?) -> String? {
        price.map { "Unlock for \($0)" }
    }

    static let priceMissing = "The price could not be loaded right now."
    static let retryPrice = "Try loading the price again"

    static func note(_ status: StoreManager.Status) -> String? {
        switch status {
        case .idle, .working:
            return nil
        case .pending:
            return "Waiting for approval. Rooms for 4 to 8 open here once the purchase is approved; if it is declined, nothing changes and you can try again."
        case .recordedNotShown:
            return "The App Store has recorded this purchase, but it has not shown up here yet. Tap Restore purchase."
        case .nothingToRestore:
            return "No earlier unlock was found for this Apple ID."
        case .failed(.unverified):
            return "The App Store's record of this purchase could not be checked, so rooms stay at 3 for now. Try Restore purchase."
        case .failed(.purchaseFailed):
            return "The purchase did not complete. Try again."
        case .failed(.restoreFailed):
            return "Restore did not complete. Check your connection and try again."
        }
    }
}
