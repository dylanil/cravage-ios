import SwiftUI

@main
struct CravageApp: App {
    @State private var coordinator = RoundCoordinator(transport: NetworkTransport(), clock: LiveClock(), entitlement: NoUnlockYet())

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
        }
    }
}
