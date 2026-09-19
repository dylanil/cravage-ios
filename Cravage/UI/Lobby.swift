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
    static func canStart(inRoom: Int, maxSize: Int) -> Bool {
        inRoom >= Roster.minimumSize && inRoom <= maxSize
    }

    /// Why the button is waiting, naming the next person to admit when there is one.
    static func startHint(inRoom: Int, maxSize: Int, pending: [String]) -> String? {
        guard !canStart(inRoom: inRoom, maxSize: maxSize) else { return nil }
        let base = "Start needs \(Roster.minimumSize) people."
        guard let next = pending.first else { return base }
        return base + " Admit \(next) to begin."
    }

    /// "1 other phone connected." - the sentence the host reads to check the room against the
    /// phones actually in front of them.
    static func connectedLine(others: Int) -> String {
        let phones = others == 1 ? "1 other phone" : "\(others) other phones"
        return "\(phones) connected. Keep the app open on every phone until the round ends."
    }
}
