import SwiftUI
import UIKit

/// Settings.
///
/// Restore purchase asks the App Store for the Apple ID's earlier unlock. It can show an App Store
/// sign-in prompt, so it runs only when tapped.
struct SettingsView: View {
    let coordinator: RoundCoordinator
    let nicknames: NicknameStore
    let store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var editingName = false
    @State private var copied = false
    @AppStorage(Appearance.key) private var appearance: Appearance = .system

    private static let privacyPolicy = URL(string: "https://dylanil.github.io/cravage-ios/privacy-policy")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(text: "You")
                        .padding(.top, 8)
                    Button { editingName = true } label: {
                        row(title: "Your name",
                            note: nicknames.hasNickname ? nicknames.nickname : "Not chosen yet",
                            chevron: true)
                    }
                    .buttonStyle(.plain)

                    SectionHeading(text: "Appearance")
                        .padding(.top, 24)
                    AppearanceSwitch(selection: $appearance)
                        .padding(.vertical, 12)

                    SectionHeading(text: "Purchase")
                        .padding(.top, 24)
                    Button { Task { await store.restore() } } label: {
                        row(title: "Restore purchase", note: purchaseNote, chevron: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.status == .working)

                    SectionHeading(text: "About Cravage")
                        .padding(.top, 24)
                    NavigationLink { WhyView() } label: {
                        row(title: "Why Cravage?", note: "What it is for, and why not just ask someone", chevron: true)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { LimitationsView() } label: {
                        row(title: "Limitations", note: "What Cravage can't do", chevron: true)
                    }
                    .buttonStyle(.plain)
                    Button { UIApplication.shared.open(Self.privacyPolicy) } label: {
                        row(title: "Privacy policy", note: "Opens in Safari", chevron: true)
                    }
                    .buttonStyle(.plain)
                    row(title: "Version", note: "\(Self.appVersion) (\(Self.build))", chevron: false)

                    SectionHeading(text: "Support")
                        .padding(.top, 24)
                    Button(action: copyDiagnostics) {
                        row(title: copied ? "Copied" : "Copy diagnostics",
                            note: "No figures, names or room names", chevron: false)
                    }
                    .buttonStyle(.plain)
                    Text("Cravage does not operate a server that receives your round data. Round history is not saved; your name is saved on this phone.")
                        .paperFont(.sans, 14)
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
                .padding(.horizontal, Paper.gutter)
                .padding(.bottom, Paper.bottomInset)
            }
            .paperBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $editingName) { NicknameSheet(nicknames: nicknames) }
        }
    }

    private var purchaseNote: String {
        if store.status == .working { return "Checking with the App Store" }
        if let note = UnlockCopy.note(store.status) { return note }
        return store.unlocked ? "Rooms for 4 to 8 people are unlocked" : "Finds an unlock bought with this Apple ID"
    }

    private func row(title: String, note: String?, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .paperFont(.serif, 20, weight: .regular)
                    .foregroundStyle(Paper.ink)
                if let note {
                    Text(note)
                        .paperFont(.sans, 14)
                        .foregroundStyle(Paper.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .paperFont(.sans, 14, weight: .semibold)
                    .accessibilityHidden(true)
                    .foregroundStyle(Paper.muted)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.hairline).frame(height: 1) }
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = Diagnostics.report(
            for: coordinator,
            appVersion: Self.appVersion,
            build: Self.build,
            systemVersion: UIDevice.current.systemVersion,
            model: Self.model)
        copied = true
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// The hardware identifier ("iPhone17,1"), which names a model and not a person.
    private static var model: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &value, &size, nil, 0)
        return String(cString: value)
    }
}

/// The three-part Appearance switch. Built from Paper type rather than the system segmented control,
/// whose labels stay one size at every Text Size; when the labels no longer fit side by side, the
/// parts stack.
private struct AppearanceSwitch: View {
    @Binding var selection: Appearance

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) { parts }
            VStack(spacing: 2) { parts }
        }
        .padding(2)
        .background(Paper.hairline, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    private var parts: some View {
        ForEach(Appearance.allCases) { choice in
            let chosen = choice == selection
            Button { selection = choice } label: {
                Text(choice.title)
                    .paperFont(.sans, 15, weight: chosen ? .semibold : .regular)
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 8)
                    .background(chosen ? Paper.card : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: chosen ? .black.opacity(0.12) : .clear, radius: 2, y: 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }
}
