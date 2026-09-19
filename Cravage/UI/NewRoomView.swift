import SwiftUI
import CravageCore

/// New room, in the Paper look. Mockup: `design/mockups/NewRoom.dc.html`.
///
/// The padlocks are a courtesy: the room is opened through the coordinator, which asks the store
/// and lets the engine enforce the answer (SPEC invariant 11). A refusal is reported here rather
/// than hidden.
struct NewRoomView: View {
    let coordinator: RoundCoordinator
    let nicknames: NicknameStore
    let entitlement: EntitlementProvider
    let onCancel: () -> Void

    @State private var form = NewRoomForm()
    @State private var opening = false
    @State private var editingName = false

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Cancel", action: onCancel)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "New room", title: "What are you averaging?", size: 34)
                        .padding(.top, 6)
                    labelField
                    Text("Everyone in the room sees this. Nearby phones can see it too, with your nickname and the group size, but never anyone's number.")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    SectionHeading(text: "How many people, including you")
                        .padding(.top, 24)
                    sizePicker
                        .padding(.top, 14)
                    Text("3 people is free. 4 to 8 people is a one-off unlock.")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .padding(.top, 10)
                    if let problem = coordinator.problem {
                        ProblemNotice(problem: problem)
                    }
                    if let note = refusal {
                        Text(note)
                            .font(Paper.sans(14))
                            .foregroundStyle(Paper.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                PrimaryButton(title: "Open room", enabled: form.canOpen && !opening, action: open)
            }
        }
        .paperBackground()
        .task {
            form.unlocked = await entitlement.hasVerifiedUnlock()
            if !nicknames.hasNickname { editingName = true }
        }
        .sheet(isPresented: $editingName) { NicknameSheet(nicknames: nicknames) }
    }

    /// The label sits on an accent rule rather than in a box, as the mockup draws it.
    private var labelField: some View {
        VStack(spacing: 0) {
            TextField("Annual bonus", text: $form.label)
                .font(Paper.serif(26, weight: .regular))
                .foregroundStyle(Paper.ink)
                .tint(Paper.accentFill)
                .submitLabel(.done)
                .padding(.bottom, 8)
            Rectangle().fill(Paper.accentFill).frame(height: 2)
        }
        .padding(.top, 18)
    }

    private var sizePicker: some View {
        HStack(spacing: 6) {
            ForEach(NewRoomForm.sizes, id: \.self) { size in
                Button { form.size = size } label: {
                    VStack(spacing: 4) {
                        Text("\(size)")
                            .font(Paper.serif(20))
                            .foregroundStyle(size == form.size ? .white : Paper.ink)
                            .frame(width: 44, height: 44)
                            .background(size == form.size ? Paper.ink : .clear, in: Circle())
                            .overlay(size == form.size ? nil : Circle().strokeBorder(Paper.hairline, lineWidth: 1.5))
                        Group {
                            if form.isLocked(size) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Paper.muted)
                            }
                        }
                        .frame(height: 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(form.isLocked(size) ? "\(size) people, locked" : "\(size) people")
                .accessibilityAddTraits(size == form.size ? [.isSelected] : [])
            }
        }
    }

    /// Honest about why a room did not open. Buying the unlock is not in the app yet, so the
    /// message says so rather than offering a purchase that does not exist.
    private var refusal: String? {
        switch coordinator.lastRejection {
        case .notEntitled:
            return "Rooms for 4 to 8 people need a one-off unlock. Buying it is not in the app yet, so only a room for 3 can be opened."
        case .invalidInput:
            return "That name for the round cannot be used. Try one without line breaks."
        case .some:
            return "The room could not be opened. Try again."
        case nil:
            return nil
        }
    }

    private func open() {
        guard nicknames.hasNickname else {
            editingName = true
            return
        }
        opening = true
        Task {
            await coordinator.createRoom(label: form.trimmedLabel, size: form.size,
                                         nickname: nicknames.nickname)
            opening = false
        }
    }
}
