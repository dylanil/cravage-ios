import CravageCore

/// What the New room screen can decide on its own, kept apart from the view so it can be tested.
///
/// `unlocked` is display only. The engine enforces the unlock at room creation (SPEC invariant 11),
/// so a locked size that reaches the button anyway is still refused there; the padlocks are a
/// courtesy, never the gate.
struct NewRoomForm: Equatable {
    static let sizes = Array(Roster.minimumSize...Roster.maximumSize)

    var label = ""
    var size = Roster.minimumSize
    /// The store's last answer for this Apple ID. False until it has answered.
    var unlocked = false

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isLocked(_ size: Int) -> Bool {
        size > Roster.minimumSize && !unlocked
    }

    var needsUnlock: Bool { isLocked(size) }

    /// The roster rejects a label it cannot carry, so the button waits for one it accepts.
    var canOpen: Bool { RoomText.isValidLabel(trimmedLabel) }

    /// Why the button is waiting, once something has been typed.
    var labelProblem: String? {
        guard !trimmedLabel.isEmpty, !canOpen else { return nil }
        return "That name can't be used. It may be too long, or have a line break or an invisible "
            + "character. Some emoji, such as \u{2764}\u{FE0F}, contain an invisible character."
    }
}
