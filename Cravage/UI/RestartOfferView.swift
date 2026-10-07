import SwiftUI
import CravageCore

/// A host's restart, waiting for this person's answer.
///
/// Decision 2026-09-13 (SPEC 13): a restart is an offer, not something done to a phone. This
/// phone sends nothing until the person accepts; an unanswered offer lapses with the host's lobby,
/// and declining leaves the room.
struct RestartOfferView: View {
    let coordinator: RoundCoordinator
    let actions: RoundActions
    let onLeave: () -> Void

    private var engine: RoundEngine { coordinator.live }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44)
            ScrollingBody {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "Round restarted", title: "The host restarted the round")
                        .padding(.top, 6)
                    if let offer = engine.restartOffer {
                        Text("\(offer.label) \u{00B7} \(offer.size) people")
                            .paperFont(.sans, 15)
                            .foregroundStyle(Paper.muted)
                            .padding(.top, 14)
                    }
                    Text("Rejoin to take part again. You will enter your figure again.")
                        .paperFont(.sans, 15)
                        .foregroundStyle(Paper.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                .padding(.horizontal, Paper.gutter)
            } actions: {
                PrimaryButton(title: "Rejoin") {
                    actions.acceptRestart()
                }
                SecondaryButton(title: "Leave room", action: onLeave)
                CountdownLabel(coordinator: coordinator) { time in "Offer ends in \(time)" }
            }
        }
        .paperBackground()
    }

}

/// A round that stopped. Mockups: the connection-lost, timeout, declined and room-full sketches.
struct FailedView: View {
    let coordinator: RoundCoordinator
    let reason: FailureReason
    let onRestart: () -> Void
    let onLeave: () -> Void

    private var engine: RoundEngine { coordinator.live }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44)
            ScrollingBody {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "Round ended", title: FailureCopy.title(reason))
                        .padding(.top, 6)
                    Text(FailureCopy.detail(reason, name: nickname))
                        .paperFont(.sans, 15)
                        .foregroundStyle(Paper.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    RestartRefusal(rejection: coordinator.lastRejection)
                        .padding(.top, 12)
                }
                .padding(.horizontal, Paper.gutter)
            } actions: {
                // The engine decides whether a restart is possible: it needs the roster and enough
                // people still connected. A refusal is reported rather than pre-empted here.
                if engine.role == .host, engine.roster != nil {
                    PrimaryButton(title: "Restart round", action: onRestart)
                }
                SecondaryButton(title: FailureCopy.leaveTitle(reason), action: onLeave)
            }
        }
        .paperBackground()
    }

    private func nickname(_ label: PartyLabel) -> String {
        engine.roster?.parties.first { $0.label == label }?.nickname ?? label.description
    }
}
