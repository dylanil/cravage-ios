import SwiftUI
import CravageCore

/// Waiting for shares. Mockup: `design/mockups/Waiting.dc.html`.
///
/// Every phone's own share has already gone by the time this screen appears, so the list is about
/// the others. It says who the round is still waiting on, and what happens when it gives up.
struct WaitingView: View {
    let coordinator: RoundCoordinator
    let onCancel: () -> Void

    private var engine: RoundEngine { coordinator.engine }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Cancel", action: onCancel)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: engine.roster?.label ?? "Round", title: title)
                        .padding(.top, 6)
                    SectionHeading(text: "Phones")
                        .padding(.top, 24)
                    if let roster = engine.roster {
                        ForEach(roster.parties, id: \.label) { party in
                            let sent = engine.sharesReceived.contains(party.label)
                            PersonRow(letter: party.label.description,
                                      name: party.nickname,
                                      note: note(for: party, sent: sent),
                                      filled: sent,
                                      showsRule: party.label != roster.parties.last?.label) {
                                StatusTag(text: sent ? "Sent" : "Waiting", done: sent)
                            }
                        }
                    }
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                CountdownLabel(coordinator: coordinator) { time in
                    "Stops waiting in \(time); the round then fails and the host can restart"
                }
            }
        }
        .paperBackground()
    }

    private var title: String {
        let size = engine.roster?.size ?? 0
        if engine.phase == .collectingConfirmations {
            return "All shares in. Checking everyone agrees."
        }
        return "\(engine.sharesReceived.count) of \(size) masked shares in"
    }

    private func note(for party: Party, sent: Bool) -> String? {
        if party.label == engine.myLetter { return "You" }
        return sent ? nil : "Still entering a figure"
    }
}
