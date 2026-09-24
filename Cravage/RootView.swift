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
            .background(PrivacyShield(onBackground: coordinator.appEnteredBackground))
            // The Paper look has no dark variant yet; pinning the appearance keeps the approved
            // colours rather than inventing an undesigned one.
            .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var screen: some View {
        let actions = RoundActions(coordinator)
        let leave = { if actions.leave() { joined = nil; idle = .home } }
        switch Screen(coordinator, idle: idle) {
        case .home:
            HomeView(coordinator: coordinator, nicknames: nicknames,
                     onNewRoom: { if actions.leave() { idle = .newRoom } },
                     onJoin: { if actions.leave() { idle = .join } })
        case .newRoom:
            NewRoomView(coordinator: coordinator, actions: actions, nicknames: nicknames, entitlement: entitlement,
                        onCancel: leave)
        case .join:
            JoinView(coordinator: coordinator, actions: actions, nicknames: nicknames,
                     onPick: { joined = $0 }, onBack: leave)
        case .lobbyHost:
            LobbyHostView(coordinator: coordinator, actions: actions, nickname: nicknames.nickname, onClose: leave)
        case .lobbyJoiner:
            LobbyJoinerView(coordinator: coordinator, hostNickname: joined?.hostNickname,
                            nickname: nicknames.nickname, onLeave: leave)
        case .restartWarning:
            RestartWarningView(coordinator: coordinator,
                               onUnderstood: actions.acknowledgeRestartWarning,
                               onLeave: leave)
        case .confirmCode:
            ConfirmCodeView(coordinator: coordinator, actions: actions, onStop: leave)
        case .enterFigure:
            EnterFigureView(coordinator: coordinator, actions: actions, onLeave: leave)
        case .waiting:
            WaitingView(coordinator: coordinator, onCancel: leave)
        case let .result(outcome):
            ResultView(coordinator: coordinator, outcome: outcome,
                       onRunAgain: actions.restart,
                       onLeave: leave)
        case let .failed(reason):
            FailedView(coordinator: coordinator, reason: reason,
                       onRestart: actions.restart,
                       onLeave: leave)
        case .restartOffer:
            RestartOfferView(coordinator: coordinator, actions: actions, onLeave: leave)
        case .interrupted:
            VStack(alignment: .leading, spacing: 20) {
                PaperHeader(eyebrow: "Round ended", title: "Keep Cravage open")
                Text("This phone was locked or Cravage moved to the background, so it left the round. Return home to create or join a new room.")
                    .font(Paper.sans(17))
                PrimaryButton(title: "Back to home", action: leave)
            }
            .padding(Paper.gutter)
        }
    }

}
