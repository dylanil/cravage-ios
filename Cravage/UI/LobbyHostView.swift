import SwiftUI
import CravageCore

/// The host's lobby. Mockup: `design/mockups/LobbyHost.dc.html`.
///
/// Admission is the host's eyes doing the work: the caution under the requests says so, and the
/// connected line counts phones so the host can compare it with the room. Nicknames arrive from
/// other phones already checked by `RoomText` on parse, so they are displayed as plain text and
/// never read as anything else.
struct LobbyHostView: View {
    let coordinator: RoundCoordinator
    let nickname: String
    let onClose: () -> Void

    private var engine: RoundEngine { coordinator.engine }
    private var inRoom: Int { engine.admittedCount + 1 }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Close", action: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: engine.label ?? "Room",
                                title: "\(inRoom) of \(engine.maxSize) in the room")
                        .padding(.top, 6)
                    if !engine.pendingJoiners.isEmpty {
                        SectionHeading(text: "Asking to join")
                            .padding(.top, 24)
                        ForEach(engine.pendingJoiners, id: \.verifyingKey) { joiner in
                            requestRow(joiner)
                        }
                        Text("Only admit someone you can see in the room.")
                            .font(Paper.sans(14))
                            .foregroundStyle(Paper.muted)
                            .padding(.top, 10)
                    }
                    SectionHeading(text: "In the room")
                        .padding(.top, 24)
                    PersonRow(letter: initial(nickname), name: nickname, note: "You, host", filled: true) {
                        Text("This phone")
                            .font(Paper.sans(14))
                            .foregroundStyle(Paper.muted)
                    }
                    ForEach(Array(engine.admittedNicknames.enumerated()), id: \.offset) { _, name in
                        PersonRow(letter: initial(name), name: name, filled: false) {
                            StatusTag(text: "Connected", done: false)
                        }
                    }
                    Text(Lobby.connectedLine(others: engine.admittedCount))
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                PrimaryButton(title: "Start round",
                              enabled: Lobby.canStart(inRoom: inRoom, maxSize: engine.maxSize)) {
                    coordinator.start(generation: engine.generation)
                }
                if let hint = Lobby.startHint(inRoom: inRoom, maxSize: engine.maxSize,
                                              pending: engine.pendingJoiners.map(\.nickname)) {
                    Text(hint)
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .multilineTextAlignment(.center)
                }
                CountdownLabel(coordinator: coordinator) { time in
                    "Room closes in \(time) if the round has not started"
                }
            }
        }
        .paperBackground()
    }

    private func requestRow(_ joiner: PendingJoiner) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PersonRow(letter: initial(joiner.nickname), name: joiner.nickname,
                      filled: false, showsRule: false) {
                EmptyView()
            }
            HStack(spacing: 10) {
                Button("Decline") {
                    coordinator.decline(joiner.verifyingKey, generation: engine.generation)
                }
                .font(Paper.sans(17))
                .foregroundStyle(Paper.danger)
                Spacer()
                Button("Admit") {
                    coordinator.admit(joiner.verifyingKey, generation: engine.generation)
                }
                .font(Paper.sans(17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .background(Paper.accentFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.bottom, 8)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.hairline).frame(height: 1) }
    }

    private func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

/// A deadline line that re-reads the clock every second.
struct CountdownLabel: View {
    let coordinator: RoundCoordinator
    let format: (String) -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let seconds = coordinator.secondsRemaining() {
                DeadlineLine(text: format(Countdown.text(seconds: seconds)))
            }
        }
    }
}
