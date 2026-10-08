import SwiftUI
import CravageCore

/// Join a room, in the Paper look: pick a room, then join it (option B, decided 2026-10-04), with an
/// empty state and a permission state.
///
/// What a room advertises is untrusted until the room code is compared on the next screens, so the
/// list says who is hosting and how many people, and promises nothing else.
///
/// Option B (decided 2026-10-04): tapping a room picks it, and the button at the bottom joins it, so
/// joining is one deliberate, named step rather than a tap on a list row.
struct JoinView: View {
    let coordinator: RoundCoordinator
    let actions: RoundActions
    let nicknames: NicknameStore
    /// Remembers which room was tapped, so the lobby can name the host it advertised.
    let onPick: (RoomAdvert) -> Void
    let onBack: () -> Void

    @State private var editingName = false
    @State private var chosenID: String?
    @State private var joinTaps = 0

    private var chosen: RoomAdvert? { JoinChoice.chosen(chosenID, in: coordinator.rooms) }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Back", showsChevron: true, action: onBack)
            ScrollingBody {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "Join a room", title: "Rooms nearby", size: 34)
                        .padding(.top, 6)
                    Rectangle().fill(Paper.ink).frame(height: 1.5).padding(.top, 18)
                    if let problem = coordinator.problem {
                        ProblemNotice(problem: problem) { actions.browse() }
                    } else {
                        if coordinator.leftIncompatibleRoom {
                            versionMismatchNotice
                        }
                        ForEach(coordinator.rooms) { room in
                            roomRow(room)
                        }
                        if coordinator.rooms.isEmpty {
                            emptyState
                        } else {
                            searchingLine(text: "Looking for more rooms...")
                        }
                    }
                }
                .padding(.horizontal, Paper.gutter)
            } actions: {
                if coordinator.problem == nil, !coordinator.rooms.isEmpty {
                    PrimaryButton(title: JoinChoice.buttonTitle(for: chosen), enabled: chosen != nil, action: join)
                    if let note = JoinChoice.note(for: chosen) {
                        Text(note)
                            .paperFont(.sans, 13)
                            .foregroundStyle(Paper.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .paperBackground()
        .sensoryFeedback(.selection, trigger: chosenID)
        .sensoryFeedback(.impact(weight: .medium), trigger: joinTaps)
        .task {
            if !nicknames.hasNickname { editingName = true }
            actions.browse()
        }
        .sheet(isPresented: $editingName) { NicknameSheet(nicknames: nicknames) }
    }

    private var versionMismatchNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(JoinChoice.versionMismatchTitle)
                .paperFont(.serif, 22)
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(JoinChoice.versionMismatchDetail)
                .paperFont(.sans, 15)
                .foregroundStyle(Paper.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }

    private func roomRow(_ room: RoomAdvert) -> some View {
        let picked = room.id == chosen?.id
        let versionNote = JoinChoice.versionNote(for: room)
        return Button {
            chosenID = room.id
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.label)
                        .paperFont(.serif, 21)
                        .foregroundStyle(Paper.ink)
                        .multilineTextAlignment(.leading)
                    Text("Host: \(room.hostNickname) \u{00B7} \(room.size) people")
                        .paperFont(.sans, 14)
                        .foregroundStyle(Paper.muted)
                    if let versionNote {
                        Text(versionNote)
                            .paperFont(.sans, 14, weight: .semibold)
                            .foregroundStyle(Paper.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A room that cannot be picked has no circle to fill.
                ZStack {
                    if !JoinChoice.canPick(room) {
                        EmptyView()
                    } else if picked {
                        Circle().fill(Paper.accentFill)
                        Image(systemName: "checkmark")
                            .paperFont(.sans, 12, weight: .bold)
                            .accessibilityHidden(true)
                            .foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Paper.hairline, lineWidth: 1.5)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(16)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: Paper.corner))
            .overlay(RoundedRectangle(cornerRadius: Paper.corner)
                .strokeBorder(picked ? Paper.accentFill : Paper.hairline, lineWidth: picked ? 2 : 1))
            .animation(.snappy(duration: 0.2), value: picked)
        }
        .buttonStyle(PressableCard())
        .disabled(!JoinChoice.canPick(room))
        .padding(.top, 14)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
        .accessibilityHint(JoinChoice.canPick(room) ? "Picks this room. Join with the button at the bottom." : "")
    }

    private func join() {
        guard let room = chosen else { return }
        guard nicknames.hasNickname else {
            editingName = true
            return
        }
        joinTaps += 1
        if actions.join(roomID: room.id, nickname: nicknames.nickname) { onPick(room) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No rooms nearby yet")
                .paperFont(.serif, 22)
                .foregroundStyle(Paper.ink)
            Text("Stand near the host and ask them to open the room.")
                .paperFont(.sans, 15)
                .foregroundStyle(Paper.muted)
                .fixedSize(horizontal: false, vertical: true)
            searchingLine(text: "Still looking...")
                .padding(.top, 4)
        }
        .padding(.top, 20)
    }

    private func searchingLine(text: String) -> some View {
        HStack(spacing: 10) {
            PulsingDot()
            Text(text)
                .paperFont(.sans, 15)
                .foregroundStyle(Paper.muted)
        }
        .padding(.vertical, 16)
    }
}

/// A card that sinks slightly under the finger, so a tap is felt as well as seen.
private struct PressableCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The accent dot with a soft ring that marks an open search.
private struct PulsingDot: View {
    @State private var wide = false

    var body: some View {
        Circle()
            .fill(Paper.accentFill)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .fill(Paper.accentFill.opacity(0.15))
                    .frame(width: wide ? 22 : 8, height: wide ? 22 : 8)
            )
            .frame(width: 22, height: 22)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    wide = true
                }
            }
            .accessibilityHidden(true)
    }
}
