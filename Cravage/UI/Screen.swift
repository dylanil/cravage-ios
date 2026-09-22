import CravageCore

/// Where the person has navigated while no round exists. The engine owns every other screen.
enum IdleScreen: Equatable {
    case home
    case newRoom
    case join

    var screen: Screen {
        switch self {
        case .home: return .home
        case .newRoom: return .newRoom
        case .join: return .join
        }
    }
}

/// The screen a phone belongs on. Kept a pure function of the round state so the routing rules can
/// be tested without rendering: SPEC's confirmation barrier means `.enterFigure` is unreachable
/// until the engine has every phone's roomcode confirmation.
enum Screen: Equatable {
    case home
    case newRoom
    case join
    case lobbyHost
    case lobbyJoiner
    case restartWarning
    case confirmCode
    case enterFigure
    case waiting
    case result(Outcome)
    case failed(FailureReason)
    case restartOffer
    case interrupted

    static func current(phase: Phase, role: Role?, hasRestartOffer: Bool,
                        restartWarningRequired: Bool = false,
                        restartWarningAcknowledged: Bool = false,
                        idle: IdleScreen) -> Screen {
        // A restart offer arrives as the failure that ended the old round; the person is asked
        // about the new one rather than shown the wreckage of the old (owner decision 2026-09-13).
        if hasRestartOffer { return .restartOffer }
        switch phase {
        case .idle: return idle.screen
        case .lobby: return role == .host ? .lobbyHost : .lobbyJoiner
        case .confirming:
            // SPEC 13: every restarted round warns before the next figure entry, whoever is in it.
            // Placing it here, ahead of the code check, puts it before anything can be sent.
            if restartWarningRequired, !restartWarningAcknowledged { return .restartWarning }
            return .confirmCode
        case .keyExchange: return .enterFigure
        case .sharing, .collectingConfirmations: return .waiting
        case let .complete(outcome): return .result(outcome)
        case let .failed(reason): return .failed(reason)
        }
    }

    @MainActor
    init(_ coordinator: RoundCoordinator, idle: IdleScreen = .home) {
        if coordinator.wasInterrupted { self = .interrupted; return }
        let engine = coordinator.live
        self = Screen.current(phase: engine.phase,
                              role: engine.role,
                              hasRestartOffer: engine.restartOffer != nil,
                              restartWarningRequired: engine.restartWarningRequired,
                              // An acknowledgement belongs to the round it was made in.
                              restartWarningAcknowledged: coordinator.restartWarningAcknowledged == engine.generation,
                              idle: idle)
    }
}
