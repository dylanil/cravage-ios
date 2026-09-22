import SwiftUI
import CravageCore

/// Both terminal screens report the engine's refusal, including the next possible action.
struct RestartRefusal: View {
    let rejection: Rejection?

    var body: some View {
        if let message {
            Text(message)
                .font(Paper.sans(14))
                .foregroundStyle(Paper.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("restart-refusal")
        }
    }

    private var message: String? {
        switch rejection {
        case .notEnoughPeople:
            return "A restart needs at least 3 people still connected. Leave this room, then create a new room for everyone to join."
        case .wrongPhase:
            return "This round can't be restarted. Leave this room, then create a new one."
        default:
            return nil
        }
    }
}
