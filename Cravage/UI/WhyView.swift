import SwiftUI

/// Why Cravage: the case for using it, for a host persuading a room (decided 2026-10-04). Reached
/// from Home and from Settings; the last answer leads on to the full Limitations list.
struct WhyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(eyebrow: "About", title: "Why use Cravage?")
                    .padding(.top, 6)
                ForEach(WhyCopy.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.question)
                            .paperFont(.serif, 19)
                            .foregroundStyle(Paper.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.answer)
                            .paperFont(.sans, 15)
                            .foregroundStyle(Paper.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Rectangle().fill(Paper.hairline).frame(height: 1) }
                }
                NavigationLink { LimitationsView() } label: {
                    Text("Everything Cravage can't do")
                        .paperFont(.sans, 15, weight: .semibold)
                        .foregroundStyle(Paper.accent)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, Paper.gutter)
            .padding(.bottom, Paper.bottomInset)
        }
        .paperBackground()
        .navigationTitle("Why Cravage")
        .navigationBarTitleDisplayMode(.inline)
    }
}
