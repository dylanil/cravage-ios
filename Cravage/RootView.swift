import SwiftUI
import CravageCore

/// Routes the round state to a screen. The mapping itself lives in `Screen` so it can be tested
/// without rendering; this view only chooses what to show and where taps go.
struct RootView: View {
    let coordinator: RoundCoordinator
    let entitlement: EntitlementProvider
    @State private var idle: IdleScreen = .home
    @State private var nicknames = NicknameStore()
    /// The room this phone tapped in the list, kept for the joiner lobby's host name. Untrusted
    /// until the room code is compared.
    @State private var joined: RoomAdvert?

    var body: some View {
        screen
            .paperBackground()
            // The Paper look has no dark variant yet; pinning the appearance keeps the approved
            // colours rather than inventing an undesigned one.
            .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var screen: some View {
        switch Screen(coordinator, idle: idle) {
        case .home:
            HomeView(nicknames: nicknames,
                     onNewRoom: { idle = .newRoom },
                     onJoin: { idle = .join })
        case .newRoom:
            NewRoomView(coordinator: coordinator, nicknames: nicknames, entitlement: entitlement,
                        onCancel: { idle = .home })
        case .join:
            JoinView(coordinator: coordinator, nicknames: nicknames,
                     onPick: { joined = $0 }, onBack: stopBrowsing)
        case .lobbyHost:
            LobbyHostView(coordinator: coordinator, nickname: nicknames.nickname, onClose: leave)
        case .lobbyJoiner:
            LobbyJoinerView(coordinator: coordinator, hostNickname: joined?.hostNickname,
                            nickname: nicknames.nickname, onLeave: leave)
        case .restartWarning:
            RestartWarningView(coordinator: coordinator,
                               onUnderstood: coordinator.acknowledgeRestartWarning,
                               onLeave: leave)
        case .confirmCode:
            ConfirmCodeView(coordinator: coordinator, onStop: leave)
        case .enterFigure:
            EnterFigureView(coordinator: coordinator, onLeave: leave)
        case .waiting:
            WaitingView(coordinator: coordinator, onCancel: leave)
        case let .result(outcome):
            ResultView(coordinator: coordinator, outcome: outcome,
                       onRunAgain: { coordinator.restart(generation: coordinator.live.generation) },
                       onLeave: leave)
        case let .failed(reason):
            FailedView(coordinator: coordinator, reason: reason,
                       onRestart: { coordinator.restart(generation: coordinator.live.generation) },
                       onLeave: leave)
        case .restartOffer:
            RestartOfferView(coordinator: coordinator, onLeave: leave)
        }
    }

    /// Backing out of the room list stops the browse rather than leaving it running behind Home.
    private func stopBrowsing() {
        coordinator.leave()
        idle = .home
    }

    private func leave() {
        coordinator.leave()
        joined = nil
        idle = .home
    }
}
