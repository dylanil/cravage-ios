import Foundation
import CravageCore

/// The deadline countdowns the mockups write as "14:12".
enum Countdown {
    static func text(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}

/// What the host's lobby can work out on its own. The engine still decides: `start` is refused
/// there if the room is too small or too full, so this only chooses what the screen says.
enum Lobby {
    /// A first round runs at the size the host chose, so Start waits until the room is full. A
    /// restart (`needsFullRoom` false) can start with whoever came back, at least the minimum.
    static func canStart(inRoom: Int, maxSize: Int, needsFullRoom: Bool = true) -> Bool {
        inRoom >= (needsFullRoom ? maxSize : Roster.minimumSize) && inRoom <= maxSize
    }

    /// Admit all is offered only when the people waiting fill the room exactly, so it never picks
    /// who is left out, and only for two or more, since Admit already handles one.
    static func canAdmitAll(inRoom: Int, maxSize: Int, pending: Int) -> Bool {
        pending >= 2 && inRoom + pending == maxSize
    }

    /// Why the button is waiting: how many are in, and the next person to admit when there is one.
    /// A restart lobby admits nobody new, so its hint names no one.
    static func startHint(inRoom: Int, maxSize: Int, pending: [String], needsFullRoom: Bool = true) -> String? {
        guard !canStart(inRoom: inRoom, maxSize: maxSize, needsFullRoom: needsFullRoom) else { return nil }
        guard needsFullRoom else { return "Start needs at least \(Roster.minimumSize) people." }
        let count = inRoom == 1 ? "Only you are in." : "\(inRoom) are in."
        let base = "Start needs all \(maxSize) people. \(count)"
        guard let next = pending.first else {
            return base + " If someone isn't coming, close this room and create a new one."
        }
        return base + (inRoom + 1 == maxSize ? " Admit \(next) to begin." : " Admit \(next) next.")
    }

    /// What the host's lobby says when the engine refuses a tap. Every refusal gets a line: a tap
    /// that silently does nothing reads as a broken button.
    static func refusal(_ rejection: Rejection?, maxSize: Int) -> String? {
        switch rejection {
        case nil:
            return nil
        case .roomFull:
            return "This room is set for \(maxSize) people and is full."
        case .notEnoughPeople:
            return "Start needs all \(maxSize) people."
        case .invalidInput:
            return "That request has already been answered, or the person has left."
        case .wrongPhase:
            return "This room can't take anyone new now. A restarted round only takes back the people from the last one."
        case .notEntitled:
            return "Rooms for 4 to 8 people need a one-off unlock."
        case .staleGeneration:
            return "The room changed just before that tap. Try again."
        default:
            return "That didn't work. Try again."
        }
    }

    /// "1 other phone connected." - the sentence the host reads to check the room against the
    /// phones actually in front of them.
    static func connectedLine(others: Int) -> String {
        let phones = others == 1 ? "1 other phone" : "\(others) other phones"
        return "\(phones) connected. Keep the app open on every phone until the round ends."
    }
}
