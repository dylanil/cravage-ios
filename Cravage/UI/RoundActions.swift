import CravageCore

/// Actions belonging to the round a screen displays. Views receive this value from RootView.
@MainActor
struct RoundActions {
    private let coordinator: RoundCoordinator
    private let generation: Int

    init(_ coordinator: RoundCoordinator) {
        self.coordinator = coordinator
        generation = coordinator.live.generation
    }

    func admit(_ key: VerifyingKey) { coordinator.admit(key, generation: generation) }
    func decline(_ key: VerifyingKey) { coordinator.decline(key, generation: generation) }
    func start() { coordinator.start(generation: generation) }
    func confirmRoomCode() { coordinator.confirmRoomCode(generation: generation) }
    func restart() { coordinator.restart(generation: generation) }
    func acceptRestart() { coordinator.acceptRestart(generation: generation) }
    @discardableResult
    func submitFigure(_ text: String) -> FixedPointError? {
        coordinator.submitFigure(text, generation: generation)
    }
    func acknowledgeRestartWarning() {
        guard coordinator.engine.generation == generation else { return }
        coordinator.acknowledgeRestartWarning()
    }
    @discardableResult
    func leave() -> Bool {
        guard coordinator.engine.generation == generation else { return false }
        coordinator.leave()
        return true
    }
}
