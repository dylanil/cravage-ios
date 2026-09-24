import SwiftUI

/// What Cravage can't do. Mockup: `design/mockups/SketchLimitations.dc.html`.
///
/// The text is the owner-approved in-app list from SPEC's "Limitations text" section, which is the
/// short form of README's Known limitations. It is council-approved: change it only with the owner.
/// The last two items are additions so the screen and README agree: the 2026-09-22 lifecycle
/// decision and the 2026-09-24 invisible-character rule, both approved by the owner on 2026-09-24.
struct LimitationsView: View {
    private let items = [
        "Same room only, up to 8 people. Everyone needs an iPhone on iOS 26 or later with the app.",
        "Figures up to 999,999,999,999.99. The masking maths hides figures perfectly only within a bounded range, so the app enforces one.",
        "If someone drops out mid-round, the round fails. The host restarts it with one tap, same room and name. If a restart changes who is in the room and people re-enter the same figures, the difference between the two results can reveal the figure of whoever left. The app warns on every restart.",
        "The maths cannot check honesty. Signatures prove who sent a masked number, not that the figure behind it was truthful.",
        "A room letter proves a distinct cryptographic key, not a distinct person or phone. The app cannot detect a host who invents extra participants on their own device. Count the other phones yourself; the app tells you how many it expects.",
        "Collusion has a floor. If everyone else in the round conspires, they can recover your figure.",
        "The average itself can be revealing, through small groups, prior knowledge, or repeated overlapping rounds.",
        "A verified transcript can be produced by a single device acting alone. It does not prove that several phones or people took part.",
        "The app trusts each phone to keep its own figure in range before masking. A modified app could submit an out-of-range figure and skew the average without any signature failing.",
        "Anyone on the same Wi-Fi can see that a round is happening, its room name, the host's nickname and the group size. Not anyone's number.",
        "If a result is later found inconsistent, an already-shown or exported result may be marked disputed afterwards. The exported file does not change, only this app's record of it, and the app will not export that round again.",
        "Locking this phone or moving Cravage to the background leaves an unfinished round. It does not resume; create or join a new room.",
        "Names and room labels can't contain invisible characters, except the joining marks some languages need. Some emoji, such as the red heart, are refused as a result.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(eyebrow: "Limitations", title: "What Cravage can't do")
                    .padding(.top, 6)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Paper.accentFill)
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)
                        Text(item)
                            .font(Paper.sans(15))
                            .foregroundStyle(Paper.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Paper.hairline).frame(height: 1) }
                }
            }
            .padding(.horizontal, Paper.gutter)
            .padding(.bottom, Paper.bottomInset)
        }
        .paperBackground()
        .navigationTitle("Limitations")
        .navigationBarTitleDisplayMode(.inline)
    }
}
