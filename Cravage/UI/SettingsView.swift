import SwiftUI
import UIKit

/// Settings. Mockup: `design/mockups/SketchSettings.dc.html`.
///
/// Restore purchase is deliberately absent until StoreKit exists (delivery step 8): a control that
/// cannot work is worse than no control.
struct SettingsView: View {
    let coordinator: RoundCoordinator
    let nicknames: NicknameStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingName = false
    @State private var copied = false

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

                    SectionHeading(text: "About Cravage")
                        .padding(.top, 24)
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
                        .font(Paper.sans(14))
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

    private func row(title: String, note: String?, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Paper.serif(20, weight: .regular))
                    .foregroundStyle(Paper.ink)
                if let note {
                    Text(note)
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
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
