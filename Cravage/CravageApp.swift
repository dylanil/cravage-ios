import SwiftUI

@main
struct CravageApp: App {
    /// One store: the coordinator asks it at room creation, and the New room and Settings screens
    /// use the same one to draw padlocks, buy and restore.
    @State private var store: StoreManager
    @State private var coordinator: RoundCoordinator
    /// Light, dark or the phone's own setting, from Settings. Set on the window, so sheets already
    /// shown change with it.
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    #if DEBUG
    @State private var stage: ScreenshotStage?
    #endif

    init() {
        // A shared transcript is deleted when the result closes; this catches an app that was
        // closed on the result screen.
        TranscriptExport.close()
        #if DEBUG
        let stage = ScreenshotStage.fromLaunchArguments()
        _stage = State(initialValue: stage)
        if let stage {
            _store = State(initialValue: stage.store)
            _coordinator = State(initialValue: stage.coordinator)
            return
        }
        #endif
        let store = StoreManager(backend: StoreKitBackend())
        _store = State(initialValue: store)
        _coordinator = State(initialValue: RoundCoordinator(transport: NetworkTransport(),
                                                            clock: LiveClock(),
                                                            entitlement: store))
    }

    var body: some Scene {
        WindowGroup {
            // Listening starts at launch: Apple delivers unfinished transactions once, right then.
            RootView(coordinator: coordinator, store: store, idle: firstScreen)
                .background(WindowAppearance(appearance: appearance))
                .task {
                    store.start()
                    #if DEBUG
                    await stage?.run(hostNickname: NicknameStore().nickname)
                    #endif
                }
        }
    }

    private var firstScreen: IdleScreen {
        #if DEBUG
        return stage?.idle ?? .home
        #else
        return .home
        #endif
    }
}
