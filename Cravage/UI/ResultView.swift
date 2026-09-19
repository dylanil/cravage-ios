import SwiftUI
import CravageCore

/// The result. Mockup: `design/mockups/Result.dc.html`, with the not-agreed, disagreement and
/// disputed wording from the sketches.
///
/// Two rules from SPEC are carried here rather than in the view's prose: a round this phone did not
/// see agreed is never exported, and a disagreement is never written as an accusation.
struct ResultView: View {
    let coordinator: RoundCoordinator
    let outcome: Outcome
    let onRunAgain: () -> Void
    let onLeave: () -> Void

    @State private var showingShares = false

    private var engine: RoundEngine { coordinator.engine }
    private var record: RoundRecord? { engine.record }

    var body: some View {
        VStack(spacing: 0) {
            PaperNavBar(trailingTitle: "Done", trailingAction: onLeave)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaperHeader(eyebrow: record?.label ?? "Round", title: OutcomeCopy.title(outcome))
                        .padding(.top, 6)
                    if OutcomeCopy.showsAverage(outcome) {
                        averageBlock
                    }
                    Text(detail)
                        .font(Paper.sans(15))
                        .foregroundStyle(Paper.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                    SectionHeading(text: "This round")
                        .padding(.top, 24)
                    sharesRow
                    if OutcomeCopy.canExport(outcome), let file = transcriptFile {
                        ShareLink(item: file) {
                            rowLabel(title: "Share transcript", note: "A file anyone can check")
                        }
                        .buttonStyle(.plain)
                    }
                    Text("The app can't check that the figures people entered were true. Round history is not saved.")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
                .padding(.horizontal, Paper.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomStack {
                if engine.role == .host {
                    PrimaryButton(title: "Run again", action: onRunAgain)
                }
                SecondaryButton(title: "Leave room", action: onLeave)
            }
        }
        .paperBackground()
        .sheet(isPresented: $showingShares) {
            SharesSheet(record: record)
        }
    }

    private var averageBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(engine.average ?? "")
                .font(Paper.mono(52))
                .tracking(-1)
                .foregroundStyle(Paper.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(caption)
                .font(Paper.sans(15))
                .foregroundStyle(Paper.muted)
        }
        .padding(.top, 18)
    }

    private var caption: String {
        let size = record?.parties.count ?? 0
        if case .partial = outcome { return "from \(size) people, not agreed" }
        return "from \(size) people"
    }

    private var detail: String {
        OutcomeCopy.detail(outcome, size: record?.parties.count ?? 0) { label in
            record?.parties.first { $0.label == label }?.nickname ?? label.description
        }
    }

    private var sharesRow: some View {
        Button { showingShares = true } label: {
            rowLabel(title: "Show the shares", note: nil)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(title: String, note: String?) -> some View {
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
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Paper.muted)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.hairline).frame(height: 1) }
    }

    /// Written only for a round this phone saw agreed. The file is the transcript the pinned
    /// verifier accepts; nothing else about the round is kept.
    private var transcriptFile: URL? {
        guard OutcomeCopy.canExport(outcome), let record,
              let transcript = Transcript.make(from: record) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cravage-transcript.json")
        do {
            try transcript.encoded().write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// The masked shares, as the transcript carries them. They are what the arithmetic check runs on,
/// and they are not anybody's figure.
private struct SharesSheet: View {
    let record: RoundRecord?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Each phone's masked share. They add up to the total; on their own they say nothing about anyone's figure.")
                        .font(Paper.sans(14))
                        .foregroundStyle(Paper.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(record?.parties ?? [], id: \.label) { party in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(party.label.description) \u{00B7} \(party.nickname)")
                                .font(Paper.sans(14, weight: .semibold))
                                .foregroundStyle(Paper.ink)
                            Text(record?.shares[party.label] ?? "")
                                .font(Paper.mono(13, weight: .regular))
                                .foregroundStyle(Paper.muted)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(Paper.gutter)
            }
            .paperBackground()
            .navigationTitle("Shares")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
