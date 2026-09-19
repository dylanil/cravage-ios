import SwiftUI
import UIKit

/// The shared honest error for a transport that cannot see or reach other phones. Used wherever a
/// problem can land: the room list, and the New room form a host is returned to when its listener
/// fails and the room closes.
struct ProblemNotice: View {
    let problem: TransportProblem
    /// Nil where the screen's own main button is the retry, as on the New room form.
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ProblemCopy.title(problem))
                .font(Paper.serif(22))
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(ProblemCopy.detail(problem))
                .font(Paper.sans(15))
                .foregroundStyle(Paper.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if ProblemCopy.offersSettings(problem) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if let retry {
                    Button("Try again", action: retry)
                }
            }
            .font(Paper.sans(17, weight: .semibold))
            .foregroundStyle(Paper.accent)
            .padding(.top, 4)
        }
        .padding(.top, 20)
    }
}
