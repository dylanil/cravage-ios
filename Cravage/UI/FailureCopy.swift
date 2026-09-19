import CravageCore

/// What a round that stopped says. Kept apart from the view so the wording rules can be tested.
///
/// The same rule as the result screen applies: a relay or a dropped connection can make an honest
/// phone look like the cause, so nothing here is written as an accusation.
enum FailureCopy {
    static func title(_ reason: FailureReason) -> String {
        switch reason {
        case .declined: return "You weren't admitted"
        case .connectionLost: return "Lost the connection to the host"
        case .hostRestarted: return "The host restarted the round"
        case .aborted: return "The host ended the round"
        case .invalidRoster, .rosterMismatch: return "The phones disagreed about who is in the room"
        default: return "The round stopped"
        }
    }

    static func detail(_ reason: FailureReason, name: (PartyLabel) -> String) -> String {
        switch reason {
        case .declined:
            return "If that's a mistake, ask the host and try again."
        case .connectionLost:
            return "The round has stopped. Nothing you entered was sent unmasked."
        case .hostRestarted:
            return "The offer to rejoin ran out. Ask the host to start another round."
        case let .timeout(stage):
            return "\(waiting(for: stage)) The round has stopped; the host can restart it with the same room."
        case let .peerLeft(letter):
            let who = letter.map { "\(name($0))'s phone" } ?? "A phone"
            return "\(who) left before the round finished. The host can restart it with the same room."
        case let .aborted(reason):
            return aborted(reason)
        case let .conflictingMessage(letter):
            return "Two different messages arrived for the same step from \(name(letter))'s phone, so nothing is shown. "
                + "This does not mean \(name(letter)) did anything wrong."
        case let .rosterMismatch(letter):
            let who = letter.map { "\(name($0))'s phone" } ?? "A phone"
            return "\(who) signed for a different room list than this one, so the round stopped. No result is shown."
        case .invalidRoster:
            return "The room list this phone was sent did not add up, so nothing was sent from here."
        }
    }

    private static func waiting(for stage: Stage) -> String {
        switch stage {
        case .lobby: return "Nobody finished joining in time."
        case .confirming: return "Not every phone confirmed the room code in time."
        case .keyExchange, .sharing: return "Not every phone sent a share in time."
        case .collectingConfirmations: return "Not every phone signed agreement in time."
        }
    }

    private static func aborted(_ reason: Wire.AbortReason) -> String {
        switch reason {
        case .hostLeft: return "The host left the room."
        case .peerLeft: return "The host stopped the round because a phone left."
        case .timeout: return "The host stopped the round because a phone did not answer in time."
        case .conflict: return "The host stopped the round because conflicting messages arrived."
        case .rosterMismatch: return "The host stopped the round because the phones disagreed about who was in it."
        }
    }

    /// A joiner that was never in the room goes back to the list; anyone else leaves the room.
    static func leaveTitle(_ reason: FailureReason) -> String {
        if case .declined = reason { return "Back to rooms" }
        return "Leave room"
    }
}

/// What a transport problem says. `TransportProblem.unavailable`'s own documentation promises an
/// honest generic error with retry; the review found no screen implementing it, so this is it.
enum ProblemCopy {
    static func title(_ problem: TransportProblem) -> String {
        switch problem {
        case .localNetworkDenied: return "Cravage can't see phones nearby"
        case .unavailable: return "Cravage can't reach the other phones"
        }
    }

    static func detail(_ problem: TransportProblem) -> String {
        switch problem {
        case .localNetworkDenied:
            return "Local Network access is turned off for Cravage. Settings > Privacy & Security > Local Network > Cravage."
        case .unavailable:
            return "Check Wi-Fi is on for every phone and that you are all on the same network, then try again."
        }
    }

    /// Only the permission case has a Settings page worth opening.
    static func offersSettings(_ problem: TransportProblem) -> Bool {
        problem == .localNetworkDenied
    }
}
