import SwiftUI
import CravageCore

/// Enter figure.
///
/// The figure is parsed by the same code the web app uses, and a parse failure is shown here with
/// nothing sent. Once the share goes, the figure is frozen for the round: one distinct share per
/// round identity, so the button says so before it is pressed.
struct EnterFigureView: View {
    let coordinator: RoundCoordinator
    let actions: RoundActions
    let onLeave: () -> Void

    @State private var text = Self.firstText
    @State private var error: FixedPointError?
    @FocusState private var focused: Bool

    private var engine: RoundEngine { coordinator.live }

    /// Empty, except in a Debug build staged for the Enter figure screenshot (ScreenshotStage).
    private static var firstText: String {
        #if DEBUG
        return ScreenshotStage.launchScene.flatMap(ScreenshotStage.draftFigure(for:)) ?? ""
        #else
        return ""
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Leave", action: onLeave)
            ScrollingBody {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: engine.roster?.label ?? "Round", title: "Your figure")
                        .padding(.top, 6)
                    figureField
                    if let error {
                        Text(error.message)
                            .paperFont(.sans, 14)
                            .foregroundStyle(Paper.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    Text(FigureCopy.limit)
                        .paperFont(.sans, 14)
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    NoteCard {
                        Image(systemName: "iphone")
                            .paperFont(.sans, 18)
                            .foregroundStyle(Paper.accent)
                    } content: {
                        Text(FigureCopy.onThisPhone)
                    }
                    .padding(.top, 18)
                    NoteCard {
                        Image(systemName: "person.2")
                            .paperFont(.sans, 17)
                            .foregroundStyle(Paper.accent)
                    } content: {
                        Text(FigureCopy.collusion(size: engine.roster?.size ?? Roster.minimumSize))
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, Paper.gutter)
            } actions: {
                PrimaryButton(title: "Send masked share", enabled: !text.isEmpty, action: send)
                Text("Once sent, your figure can't be changed for this round.")
                    .paperFont(.sans, 14)
                    .foregroundStyle(Paper.muted)
                    .multilineTextAlignment(.center)
                CountdownLabel(coordinator: coordinator) { time in "Stops waiting in \(time)" }
            }
        }
        .paperBackground()
        .onAppear { focused = true }
    }

    private var figureField: some View {
        VStack(spacing: 0) {
            TextField("0.00", text: $text)
                .accessibilityLabel("Your figure")
                .paperFont(.mono, 42, weight: .semibold)
                .foregroundStyle(Paper.ink)
                .tint(Paper.accentFill)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .focused($focused)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.bottom, 8)
                .onChange(of: text) { _, _ in error = nil }
            Rectangle().fill(Paper.accentFill).frame(height: 2)
            HStack {
                Button("Change sign (+/-)") { text = FigureEditing.changingSign(text) }
                    .accessibilityLabel("Change sign")
                Spacer()
                Button("Decimal point (.)") { text = FigureEditing.appendingDecimalPoint(text) }
                    .accessibilityLabel("Add a decimal point")
            }
            .paperFont(.sans, 14, weight: .semibold)
            .foregroundStyle(Paper.accent)
            .frame(minHeight: 44)
        }
        .padding(.top, 18)
    }

    private func send() {
        error = actions.submitFigure(text)
    }
}
