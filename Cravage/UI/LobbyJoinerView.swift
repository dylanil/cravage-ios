import SwiftUI
import CravageCore

/// The joiner's lobby. Mockup: `design/mockups/LobbyJoiner.dc.html`.
///
/// The mockup lists everyone already in the room. A joiner cannot truthfully do that: the host
/// sends `welcome` (label and size) and then, only at lock, the roster. Until then this phone knows
/// the room it tapped, its own name, and nothing about the others, so the list says so rather than
/// inventing names. Raised with the owner; a protocol change would be needed to do more.
struct LobbyJoinerView: View {
    let coordinator: RoundCoordinator
    /// The name this room advertised. Untrusted until the room code is compared.
    let hostNickname: String?
    let nickname: String
    let onLeave: () -> Void

    private var engine: RoundEngine { coordinator.engine }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Leave", action: onLeave)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GatherIllustration()
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    PaperHeader(eyebrow: engine.label ?? "Room", title: waitingTitle)
                    Text("You are in. Keep the app open; the round begins when the room is full.")
                        .font(Paper.sans(15))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    SectionHeading(text: "In the room")
                        .padding(.top, 24)
                    if let hostNickname {
                        PersonRow(letter: initial(hostNickname), name: hostNickname,
                                  note: "Host", filled: false) { EmptyView() }
                    }
                    PersonRow(letter: initial(nickname), name: nickname, note: "You", filled: true) {
                        EmptyView()
                    }
                    Text("Everyone else appears when the host starts and every phone shows the room code.")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                CountdownLabel(coordinator: coordinator) { time in "Stops waiting in \(time)" }
            }
        }
        .paperBackground()
    }

    private var waitingTitle: String {
        if let hostNickname { return "Waiting for \(hostNickname) to start" }
        return "Waiting for the host to start"
    }

    private func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}
