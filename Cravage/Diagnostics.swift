import Foundation
import CravageCore

/// A support report someone can paste into an email without reading it.
///
/// CLAUDE.md: figures, keys, masks, names and labels never appear in diagnostics. So this carries
/// only counts, enum names and build information - never a nickname, a room name, a figure, a key,
/// the room code or the roster hash. Everything here is either a number or a fixed word chosen in
/// this file, which is what makes that promise checkable.
@MainActor
enum Diagnostics {
    static func report(for coordinator: RoundCoordinator, appVersion: String, build: String,
                       systemVersion: String, model: String) -> String {
        let engine = coordinator.engine
        var lines = [
            "Cravage diagnostics",
            "app: \(appVersion) (\(build))",
            "ios: \(systemVersion)",
            "device: \(model)",
            "protocol: \(CravageCore.protocolVersion)",
            "role: \(name(engine.role))",
            "phase: \(name(engine.phase))",
            "generation: \(engine.generation)",
        ]
        if let roster = engine.roster {
            lines.append("parties: \(roster.size)")
            lines.append("confirmed: \(engine.confirmedLetters.count)")
            lines.append("shares in: \(engine.sharesReceived.count)")
        } else {
            lines.append("room size: \(engine.maxSize)")
            lines.append("asking to join: \(engine.pendingJoiners.count)")
            lines.append("admitted: \(engine.admittedCount)")
        }
        lines.append("rooms seen: \(coordinator.rooms.count)")
        lines.append("interrupted: \(coordinator.wasInterrupted)")
        if let problem = coordinator.problem {
            lines.append("transport: \(name(problem))")
        }
        if let rejection = coordinator.lastRejection {
            lines.append("last refusal: \(name(rejection))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Fixed words

    // Every name below is written out here rather than taken from a description, so a type that
    // gains a nickname or a label in its own description cannot leak it through this report.

    private static func name(_ role: Role?) -> String {
        switch role {
        case .host: return "host"
        case .joiner: return "joiner"
        case nil: return "none"
        }
    }

    private static func name(_ phase: Phase) -> String {
        switch phase {
        case .idle: return "idle"
        case .lobby: return "lobby"
        case .confirming: return "confirming"
        case .keyExchange: return "key exchange"
        case .sharing: return "sharing"
        case .collectingConfirmations: return "collecting confirmations"
        case let .complete(outcome): return "complete, \(name(outcome))"
        case let .failed(reason): return "failed, \(name(reason))"
        }
    }

    private static func name(_ outcome: Outcome) -> String {
        switch outcome {
        case .agreed: return "agreed"
        case let .mismatch(letters): return "mismatch (\(letters.count))"
        case let .partial(missing): return "partial (\(missing.count) missing)"
        case .disputed: return "disputed"
        }
    }

    private static func name(_ reason: FailureReason) -> String {
        switch reason {
        case let .timeout(stage): return "timeout in \(name(stage))"
        case .peerLeft: return "a phone left"
        case .connectionLost: return "connection lost"
        case .aborted: return "host ended it"
        case .conflictingMessage: return "conflicting message"
        case .rosterMismatch: return "roster mismatch"
        case .invalidRoster: return "invalid roster"
        case .declined: return "not admitted"
        case .hostRestarted: return "host restarted"
        }
    }

    private static func name(_ stage: Stage) -> String {
        switch stage {
        case .lobby: return "lobby"
        case .confirming: return "confirming"
        case .keyExchange: return "key exchange"
        case .sharing: return "sharing"
        case .collectingConfirmations: return "collecting confirmations"
        }
    }

    private static func name(_ problem: TransportProblem) -> String {
        switch problem {
        case .localNetworkDenied: return "local network denied"
        case .unavailable: return "unavailable"
        }
    }

    private static func name(_ rejection: Rejection) -> String {
        switch rejection {
        case .message: return "bad message"
        case .wrongSession: return "wrong session"
        case .notFromHost: return "not from host"
        case .unknownSender: return "unknown sender"
        case .wrongPhase: return "wrong phase"
        case .staleGeneration: return "stale generation"
        case .invalidContent: return "invalid content"
        case .duplicateKey: return "duplicate key"
        case .queueFull: return "queue full"
        case .flood: return "flood"
        case .notEntitled: return "not entitled"
        case .roomFull: return "room full"
        case .notEnoughPeople: return "not enough people"
        case .figureFrozen: return "figure frozen"
        case .outOfDomain: return "out of domain"
        case .invalidInput: return "invalid input"
        }
    }
}
