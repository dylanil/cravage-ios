import CravageCore

/// Actions belonging to one screen visit and round. Capture before scheduling work, never
/// inside its Task. RootView invalidates the visit on navigation; the coordinator does so on
/// backgrounding, even while idle. Round generation independently protects restarts.
@MainActor
struct RoundActions {
    private let coordinator: RoundCoordinator
    private let generation: Int
    private let epoch: Int

    init(_ coordinator: RoundCoordinator) {
        self.coordinator = coordinator
        generation = coordinator.live.generation
        epoch = coordinator.actionEpoch
    }

    private var isCurrent: Bool {
        coordinator.engine.generation == generation && coordinator.actionEpoch == epoch
    }

    func createRoom(label: String, size: Int, nickname: String) async {
        guard isCurrent else { return }
        await coordinator.createRoom(label: label, size: size, nickname: nickname)
    }
    @discardableResult
    func join(roomID: String, nickname: String) -> Bool {
        guard isCurrent else { return false }
        coordinator.join(roomID: roomID, nickname: nickname)
        return coordinator.engine.phase == .lobby && coordinator.engine.role == .joiner
    }
    func browse() { if isCurrent { coordinator.browse() } }

    func admit(_ key: VerifyingKey) { if isCurrent { coordinator.admit(key, generation: generation) } }
    func decline(_ key: VerifyingKey) { if isCurrent { coordinator.decline(key, generation: generation) } }
    func start() { if isCurrent { coordinator.start(generation: generation) } }
    func confirmRoomCode() { if isCurrent { coordinator.confirmRoomCode(generation: generation) } }
    func restart() { if isCurrent { coordinator.restart(generation: generation) } }
    func acceptRestart() { if isCurrent { coordinator.acceptRestart(generation: generation) } }
    @discardableResult
    func submitFigure(_ text: String) -> FixedPointError? {
        guard isCurrent else { return nil }
        return coordinator.submitFigure(text, generation: generation)
    }
    func acknowledgeRestartWarning() {
        guard isCurrent else { return }
        coordinator.acknowledgeRestartWarning()
    }
    @discardableResult
    func leave() -> Bool {
        guard isCurrent else { return false }
        coordinator.leave()
        return true
    }
}
