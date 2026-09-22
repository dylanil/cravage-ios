import SwiftUI
import CravageCore

/// Shown on every restarted round before anything can be sent. Mockup:
/// `design/mockups/SketchRestartWarning.dc.html`; wording in SPEC 13, with the misleading
/// reassurance removed by owner decision on 2026-09-22.
///
/// SPEC 13, as the owner revised it on 2026-09-13: subtracting two sums to isolate a dropped
/// party's figure is inherent to restarting with the same figures and cannot be fixed with
/// cryptography, so the control is to surface the risk while it is live. A dishonest host can make
/// a changed roster look unchanged, so the warning appears on every restart, whoever is in the new
/// roster; a visibly smaller or renamed roster gets the stronger line as well.
struct RestartWarningView: View {
    let coordinator: RoundCoordinator
    let onUnderstood: () -> Void
    let onLeave: () -> Void

    private var engine: RoundEngine { coordinator.live }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "Before you go on", title: "This is a restarted round")
                        .padding(.top, 6)
                    if engine.restartRosterChanged {
                        NoteCard {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 18))
                                .foregroundStyle(Paper.accent)
                        } content: {
                            Text("This round has fewer people, or different names, than the last one.")
                        }
                        .padding(.top, 18)
                    }
                    Text("If the group has changed and people enter the same figures as last time, comparing the two results can reveal someone's figure.")
                        .font(Paper.sans(15))
                        .foregroundStyle(Paper.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                PrimaryButton(title: "I understand", action: onUnderstood)
                SecondaryButton(title: "Leave room", action: onLeave)
            }
        }
        .paperBackground()
    }
}
