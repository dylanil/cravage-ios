import SwiftUI

@main
struct CravageApp: App {
    /// One entitlement provider: the coordinator asks it at room creation, and the New room screen
    /// reads the same answer to draw its padlocks.
    @State private var entitlement: EntitlementProvider = NoUnlockYet()
    @State private var coordinator: RoundCoordinator

    init() {
        let entitlement = NoUnlockYet()
        _entitlement = State(initialValue: entitlement)
        _coordinator = State(initialValue: RoundCoordinator(transport: NetworkTransport(),
                                                            clock: LiveClock(),
                                                            entitlement: entitlement))
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, entitlement: entitlement)
        }
    }
}
