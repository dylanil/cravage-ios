import SwiftUI

/// Home, in the Paper look: the promise, the three steps, and the two ways into a round.
/// Mockup: `design/mockups/Main.dc.html`.
struct HomeView: View {
    let nicknames: NicknameStore
    let onNewRoom: () -> Void
    let onJoin: () -> Void
    @State private var editingName = false

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let steps = [
        Step(id: 1, title: "Gather in one room",
             detail: "Everyone opens Cravage on their own phone."),
        Step(id: 2, title: "Match the code",
             detail: "Each screen shows the same room code. Check it together."),
        Step(id: 3, title: "Only the average appears",
             detail: "Each phone sends a masked share. Nobody sees a number."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    PaperHeader(eyebrow: "Cravage",
                                title: "An average everyone trusts, a number nobody sees.",
                                size: 38)
                        .padding(.top, 10)
                    VStack(spacing: 0) {
                        ForEach(steps) { step in
                            stepRow(step)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                PrimaryButton(title: "New room", action: onNewRoom)
                SecondaryButton(title: "Join a room", action: onJoin)
                nicknameLine
            }
        }
        .paperBackground()
        .sheet(isPresented: $editingName) {
            NicknameSheet(nicknames: nicknames)
        }
    }

    @ViewBuilder
    private func stepRow(_ step: Step) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(step.id)")
                .font(Paper.serif(44, weight: .regular))
                .foregroundStyle(Paper.accentFill)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(Paper.serif(21))
                    .foregroundStyle(Paper.ink)
                Text(step.detail)
                    .font(Paper.sans(15))
                    .foregroundStyle(Paper.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            illustration(for: step.id)
                .frame(width: 72, height: 56)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Paper.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.id). \(step.title). \(step.detail)")
    }

    @ViewBuilder
    private func illustration(for step: Int) -> some View {
        switch step {
        case 1: GatherIllustration()
        case 2: MatchCodeIllustration()
        default: MaskedShareIllustration()
        }
    }

    /// The mockup runs this as one sentence with an inline link; it is stacked here so the action
    /// is a real button for VoiceOver and for a large-text layout.
    private var nicknameLine: some View {
        VStack(spacing: 2) {
            if nicknames.hasNickname {
                (Text("You appear as ")
                 + Text(nicknames.nickname).foregroundStyle(Paper.ink).bold()
                 + Text("."))
                    .font(Paper.sans(15))
                    .foregroundStyle(Paper.muted)
            } else {
                Text("You have not chosen a name yet.")
                    .font(Paper.sans(15))
                    .foregroundStyle(Paper.muted)
            }
            Button(nicknames.hasNickname ? "Change" : "Choose a name") { editingName = true }
                .font(Paper.sans(15))
                .foregroundStyle(Paper.accent)
        }
        .multilineTextAlignment(.center)
    }
}

/// The nickname editor. The name is saved on this phone and shown to the others in the room.
struct NicknameSheet: View {
    let nicknames: NicknameStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var rejected = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("The others in the room see this name next to your letter. It is saved on this phone.")
                    .font(Paper.sans(15))
                    .foregroundStyle(Paper.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Your name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(Paper.sans(17))
                    .submitLabel(.done)
                    .onSubmit(save)
                if rejected {
                    Text("Pick a name with no line breaks, and not only spaces.")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.danger)
                }
                Spacer()
            }
            .padding(Paper.gutter)
            .paperBackground()
            .navigationTitle("Your name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .onAppear { text = nicknames.nickname }
    }

    private func save() {
        if nicknames.save(text) {
            dismiss()
        } else {
            rejected = true
        }
    }
}
