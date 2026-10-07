import SwiftUI

/// Home, in the Paper look: the promise, the three steps, and the two ways into a round.
/// The brand sits in the top bar as the app icon and the name (decided 2026-10-04: the old "CRAVAGE"
/// eyebrow read as bland), which also frees the line that made the page scroll a little on every
/// phone. It scrolls only when it cannot fit, as with large text.
struct HomeView: View {
    let coordinator: RoundCoordinator
    let nicknames: NicknameStore
    let store: StoreManager
    let onNewRoom: () -> Void
    let onJoin: () -> Void
    @State private var editingName = false
    @State private var showingSettings = false
    @State private var showingWhy = false
    @Environment(\.dynamicTypeSize) private var typeSize

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
             detail: "Each phone sends a masked share, not your figure."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // The brand on the left; the gear the Home mockup has always carried on the right.
            HStack(spacing: 10) {
                Image("BrandMark")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 30 * 0.2237, style: .continuous))
                    .accessibilityHidden(true)
                Text("Cravage")
                    .paperFont(.serif, 22, weight: .bold)
                    .tracking(-0.3)
                    .foregroundStyle(Paper.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .paperFont(.sans, 20, weight: .regular)
                        .foregroundStyle(Paper.ink)
                }
                .accessibilityLabel("Settings")
            }
            .frame(minHeight: 44)
            .padding(.leading, Paper.gutter)
            .padding(.trailing, 16)
            // A top bar: it grows to the largest standard text size, not into the accessibility ones.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if typeSize.isAccessibilitySize {
                ScrollingBody { promise(headline: 30, compact: true) } actions: { actions }
            } else {
                // The largest headline that lets the whole page fit; scrolling only as a last resort.
                // Each candidate is the whole page, buttons included, so the fit is measured against
                // everything that has to share the height.
                ViewThatFits(in: .vertical) {
                    page(headline: 38)
                    page(headline: 34)
                    page(headline: 30)
                    page(headline: 30, compact: true)
                    page(headline: 27, compact: true)
                    ScrollView { page(headline: 27, compact: true) }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .paperBackground()
        .sheet(isPresented: $editingName) {
            NicknameSheet(nicknames: nicknames)
        }
        .sheet(isPresented: $showingWhy) {
            NavigationStack {
                WhyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingWhy = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(coordinator: coordinator, nicknames: nicknames, store: store)
        }
    }

    private func page(headline: CGFloat, compact: Bool = false) -> some View {
        VStack(spacing: 0) {
            promise(headline: headline, compact: compact)
            Spacer(minLength: 0)
            BottomStack { actions }
        }
    }

    @ViewBuilder
    private var actions: some View {
        PrimaryButton(title: "New room", action: onNewRoom)
        SecondaryButton(title: "Join a room", action: onJoin)
        nicknameLine
    }

    /// `compact` is for narrower phones, where step text wraps onto more lines: smaller drawings give
    /// the words more width, and the rows sit closer together.
    private func promise(headline: CGFloat, compact: Bool = false) -> some View {
        VStack(spacing: 0) {
            // Non-breaking spaces keep each short sentence whole, so a line never ends on a lone "No".
            Text("Aggregate your private data without an aggregator. No\u{00A0}third\u{00A0}parties. No\u{00A0}middleman.")
                .paperFont(.serif, headline)
                .tracking(-0.3)
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(steps) { step in
                    stepRow(step, compact: compact)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, Paper.gutter)
    }

    @ViewBuilder
    private func stepRow(_ step: Step, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: compact ? 12 : 16) {
            Text("\(step.id)")
                .paperFont(.serif, 44, weight: .regular)
                .foregroundStyle(Paper.accentFill)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .paperFont(.serif, 21)
                    .foregroundStyle(Paper.ink)
                Text(step.detail)
                    .paperFont(.sans, 15)
                    .foregroundStyle(Paper.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            illustration(for: step.id)
                .frame(width: compact ? 54 : 72, height: compact ? 42 : 56)
        }
        .padding(.vertical, compact ? 10 : 13)
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

    /// The name and its Change on one line, then "Why use Cravage?" centred under it (decided
    /// 2026-10-04: centred and lower down). One line for the name is what makes room for the link:
    /// the 11 Pro has no spare height above the buttons. Stacked again when the line will not fit.
    private var nicknameLine: some View {
        VStack(spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { nameText; changeButton }
                VStack(spacing: 2) { nameText; changeButton }
            }
            Button("Why use Cravage?") { showingWhy = true }
                .paperFont(.sans, 15, weight: .semibold)
                .foregroundStyle(Paper.accent)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var nameText: some View {
        if nicknames.hasNickname {
            (Text("You appear as ")
             + Text(nicknames.nickname).foregroundStyle(Paper.ink).bold()
             + Text("."))
                .paperFont(.sans, 15)
                .foregroundStyle(Paper.muted)
        } else {
            Text("You have not chosen a name yet.")
                .paperFont(.sans, 15)
                .foregroundStyle(Paper.muted)
        }
    }

    private var changeButton: some View {
        Button(nicknames.hasNickname ? "Change" : "Choose a name") { editingName = true }
            .paperFont(.sans, 15)
            .foregroundStyle(Paper.accent)
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
                    .paperFont(.sans, 15)
                    .foregroundStyle(Paper.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Your name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .paperFont(.sans, 17)
                    .submitLabel(.done)
                    .onSubmit(save)
                if rejected {
                    Text("Pick a name with no line breaks or invisible characters, and not only spaces. Some emoji, such as \u{2764}\u{FE0F}, contain an invisible character.")
                        .fixedSize(horizontal: false, vertical: true)
                        .paperFont(.sans, 14)
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
