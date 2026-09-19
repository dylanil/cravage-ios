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

    private var engine: RoundEngine { coordinator.live }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Leave", action: onLeave)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GatherIllustration()
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    PaperHeader(eyebrow: engine.label ?? "Room", title: "Waiting for the host to start")
                    Text("You've asked to join. The host admits everyone, then starts the round. Keep the app open.")
                        .font(Paper.sans(15))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    NoteCard {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 18))
                            .foregroundStyle(Paper.accent)
                    } content: {
                        advertisedLine
                    }
                    .padding(.top, 18)
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

    /// Everything a joiner has before the roster locks came from the Bonjour advert, which any
    /// nearby phone can write. The screen says so instead of listing people as though they were
    /// known (SPEC section 3, and the fresh review of 2026-09-19).
    private var advertisedLine: Text {
        guard let hostNickname else {
            return Text("Names appear, checked, when the room code does.")
        }
        return Text("This room advertises ")
            + Text(hostNickname).foregroundStyle(Paper.ink).bold()
            + Text(" as the host. Nothing here has been checked yet: every name appears, checked against a signed list, when the room code does.")
    }
}
