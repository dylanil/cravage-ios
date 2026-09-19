import SwiftUI
import CravageCore

/// Routes the round state to a screen. The mapping itself lives in `Screen` so it can be tested
/// without rendering; this view only chooses what to show and where taps go.
struct RootView: View {
    let coordinator: RoundCoordinator
    @State private var idle: IdleScreen = .home
    @State private var nicknames = NicknameStore()

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
            Unbuilt(name: "New room", back: { idle = .home })
        case .join:
            Unbuilt(name: "Join a room", back: { idle = .home })
        case .lobbyHost:
            Unbuilt(name: "Lobby (host)", back: leave)
        case .lobbyJoiner:
            Unbuilt(name: "Lobby (joiner)", back: leave)
        case .confirmCode:
            Unbuilt(name: "Check the code", back: leave)
        case .enterFigure:
            Unbuilt(name: "Enter figure", back: leave)
        case .waiting:
            Unbuilt(name: "Waiting for shares", back: leave)
        case .result:
            Unbuilt(name: "Result", back: leave)
        case .failed:
            Unbuilt(name: "Round ended", back: leave)
        case .restartOffer:
            Unbuilt(name: "Restart offered", back: leave)
        }
    }

    private func leave() {
        coordinator.leave()
        idle = .home
    }
}

/// A screen that is routed but not yet built. Replaced screen by screen; it says plainly that it is
/// unfinished rather than pretending to be the real thing.
private struct Unbuilt: View {
    let name: String
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PaperHeader(eyebrow: "Not built yet", title: name)
                .padding(.horizontal, Paper.gutter)
            Text("This screen is designed but not written yet.")
                .font(Paper.sans(15))
                .foregroundStyle(Paper.muted)
                .padding(.horizontal, Paper.gutter)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            BottomStack {
                SecondaryButton(title: "Back", action: back)
            }
        }
    }
}
