import SwiftUI
import UIKit
import CravageCore

/// Join a room, in the Paper look. Mockup: `design/mockups/Join.dc.html`, with the empty and
/// permission states from `SketchJoinEmpty` and `SketchPermission`.
///
/// What a room advertises is untrusted until the room code is compared on the next screens, so the
/// list says who is hosting and how many people, and promises nothing else.
struct JoinView: View {
    let coordinator: RoundCoordinator
    let nicknames: NicknameStore
    /// Remembers which room was tapped, so the lobby can name the host it advertised.
    let onPick: (RoomAdvert) -> Void
    let onBack: () -> Void

    @State private var editingName = false

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Back", showsChevron: true, action: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: "Join a room", title: "Rooms nearby", size: 34)
                        .padding(.top, 6)
                    Rectangle().fill(Paper.ink).frame(height: 1.5).padding(.top, 18)
                    if coordinator.problem == .localNetworkDenied {
                        permissionDenied
                    } else {
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
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
        }
        .paperBackground()
        .task {
            if !nicknames.hasNickname { editingName = true }
            coordinator.browse()
        }
        .sheet(isPresented: $editingName) { NicknameSheet(nicknames: nicknames) }
    }

    private func roomRow(_ room: RoomAdvert) -> some View {
        Button {
            guard nicknames.hasNickname else {
                editingName = true
                return
            }
            onPick(room)
            coordinator.join(roomID: room.id, nickname: nicknames.nickname)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.label)
                        .font(Paper.serif(20, weight: .regular))
                        .foregroundStyle(Paper.ink)
                        .multilineTextAlignment(.leading)
                    Text("Host: \(room.hostNickname) \u{00B7} \(room.size) people")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Paper.muted)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .overlay(alignment: .bottom) { Rectangle().fill(Paper.hairline).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No rooms nearby yet")
                .font(Paper.serif(22))
                .foregroundStyle(Paper.ink)
            Text("Stand near the host and ask them to open the room.")
                .font(Paper.sans(15))
                .foregroundStyle(Paper.muted)
                .fixedSize(horizontal: false, vertical: true)
            searchingLine(text: "Still looking...")
                .padding(.top, 4)
        }
        .padding(.top, 20)
    }

    private var permissionDenied: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cravage can't see phones nearby")
                .font(Paper.serif(22))
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Local Network access is turned off for Cravage. Settings > Privacy & Security > Local Network > Cravage.")
                .font(Paper.sans(15))
                .foregroundStyle(Paper.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Try again") { coordinator.browse() }
            }
            .font(Paper.sans(17, weight: .semibold))
            .foregroundStyle(Paper.accent)
            .padding(.top, 4)
        }
        .padding(.top, 20)
    }

    private func searchingLine(text: String) -> some View {
        HStack(spacing: 10) {
            PulsingDot()
            Text(text)
                .font(Paper.sans(15))
                .foregroundStyle(Paper.muted)
        }
        .padding(.vertical, 16)
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
