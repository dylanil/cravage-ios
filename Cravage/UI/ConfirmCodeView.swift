import SwiftUI
import CravageCore

/// Check the code. Mockup: `design/mockups/ConfirmCode.dc.html`.
///
/// This is the confirmation barrier the protocol rests on: nothing of this phone's figure leaves
/// until the person has compared the code with the phones actually in the room and every other
/// phone has signed the same comparison. SPEC invariant 12 asks for the count of *other* phones,
/// so the note gives the number to count rather than the size of the room.
struct ConfirmCodeView: View {
    let coordinator: RoundCoordinator
    let onStop: () -> Void

    private var engine: RoundEngine { coordinator.live }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "Check the code", title: "Is this on every phone?")
                        .padding(.top, 6)
                    codeBlock
                    NoteCard {
                        Image(systemName: "iphone")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Paper.accent)
                    } content: {
                        countLine
                    }
                    .padding(.top, 14)
                    SectionHeading(text: "Confirmed")
                        .padding(.top, 24)
                    if let roster = engine.roster {
                        ForEach(roster.parties, id: \.label) { party in
                            PersonRow(letter: party.label.description,
                                      name: party.nickname,
                                      note: note(for: party),
                                      filled: engine.confirmedLetters.contains(party.label),
                                      showsRule: party.label != roster.parties.last?.label) {
                                if engine.confirmedLetters.contains(party.label) {
                                    StatusTag(text: "Checked", done: true)
                                } else {
                                    StatusTag(text: "Checking", done: false)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                PrimaryButton(title: engine.localConfirmed ? "Waiting for the others" : "I checked, the codes match",
                              enabled: !engine.localConfirmed) {
                    coordinator.confirmRoomCode(generation: engine.generation)
                }
                QuietButton(title: "The codes don't match", tint: Paper.danger, action: onStop)
                CountdownLabel(coordinator: coordinator) { time in "Stops waiting in \(time)" }
            }
        }
        .paperBackground()
    }

    /// The room code between two heavy rules, in the monospace the room code always uses.
    private var codeBlock: some View {
        VStack(spacing: 4) {
            Text("\(engine.roster?.label ?? "") \u{00B7} \(engine.roster?.size ?? 0) people")
                .font(Paper.sans(13))
                .foregroundStyle(Paper.muted)
            code
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .overlay(alignment: .top) { Rectangle().fill(Paper.ink).frame(height: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.ink).frame(height: 2) }
        .padding(.top, 18)
    }

    private var code: some View {
        let text = engine.roster?.fingerprint.code ?? ""
        let halves = text.split(separator: "-", maxSplits: 1).map(String.init)
        return HStack(spacing: 0) {
            if halves.count == 2 {
                Text(halves[0])
                Text("-").foregroundStyle(Paper.accentFill)
                Text(halves[1])
            } else {
                Text(text)
            }
        }
        .font(Paper.mono(44))
        .tracking(3)
        .foregroundStyle(Paper.ink)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room code \(text.map { String($0) }.joined(separator: " "))")
    }

    private var countLine: Text {
        let others = engine.otherPhonesExpected
        let phones = others == 1 ? "1" : "\(others)"
        return Text("Look up and count the other phones.")
            .font(Paper.serif(17))
            + Text(" There should be exactly \(phones), each showing this code. If you count more or fewer, or a code differs, stop.")
    }

    private func note(for party: Party) -> String? {
        let isYou = party.label == engine.myLetter
        let isHost = party.label == engine.hostLetter
        switch (isYou, isHost) {
        case (true, true): return "You, host"
        case (true, false): return "You"
        case (false, true): return "Host"
        case (false, false): return nil
        }
    }
}
