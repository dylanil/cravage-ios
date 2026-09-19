import SwiftUI
import CravageCore

/// Enter figure. Mockup: `design/mockups/EnterFigure.dc.html`.
///
/// The figure is parsed by the same code the web app uses, and a parse failure is shown here with
/// nothing sent. Once the share goes, the figure is frozen for the round: one distinct share per
/// round identity, so the button says so before it is pressed.
struct EnterFigureView: View {
    let coordinator: RoundCoordinator
    let onLeave: () -> Void

    @State private var text = ""
    @State private var error: FixedPointError?
    @FocusState private var focused: Bool

    private var engine: RoundEngine { coordinator.live }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(title: "Leave", action: onLeave)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: engine.roster?.label ?? "Round", title: "Your figure")
                        .padding(.top, 6)
                    figureField
                    if let error {
                        Text(error.message)
                            .font(Paper.sans(14))
                            .foregroundStyle(Paper.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    Text(FigureCopy.limit)
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    NoteCard {
                        Image(systemName: "iphone")
                            .font(.system(size: 18))
                            .foregroundStyle(Paper.accent)
                    } content: {
                        Text(FigureCopy.onThisPhone)
                    }
                    .padding(.top, 18)
                    NoteCard {
                        Image(systemName: "person.2")
                            .font(.system(size: 17))
                            .foregroundStyle(Paper.accent)
                    } content: {
                        Text(FigureCopy.collusion(size: engine.roster?.size ?? Roster.minimumSize))
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                PrimaryButton(title: "Send masked share", enabled: !text.isEmpty, action: send)
                Text("Once sent, your figure can't be changed for this round.")
                    .font(Paper.sans(14))
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
                .font(Paper.mono(42, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .tint(Paper.accentFill)
                .keyboardType(.decimalPad)
                .focused($focused)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.bottom, 8)
                .onChange(of: text) { _, _ in error = nil }
            Rectangle().fill(Paper.accentFill).frame(height: 2)
        }
        .padding(.top, 18)
    }

    private func send() {
        error = coordinator.submitFigure(text, generation: engine.generation)
    }
}
