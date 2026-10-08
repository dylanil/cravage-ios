import Foundation

/// Join, option B (decided 2026-10-04): the person picks a room, then joins it with one clear button.
/// Kept apart from the view so the rules are tested: a chosen room that stops advertising is no
/// longer chosen, a room on another app version cannot be chosen, and the notes claim only what is
/// true.
enum JoinChoice {
    /// The chosen room, if it is still in the list and this phone can join it.
    static func chosen(_ id: String?, in rooms: [RoomAdvert]) -> RoomAdvert? {
        guard let id else { return nil }
        return rooms.first { $0.id == id && canPick($0) }
    }

    static func canPick(_ room: RoomAdvert) -> Bool { room.isCompatible }

    /// Shown on a room this phone cannot join. Neither phone can tell which of the two is behind,
    /// so it asks for both to be updated.
    static func versionNote(for room: RoomAdvert) -> String? {
        room.isCompatible ? nil : "Needs a compatible version of Cravage. Update the app on both phones."
    }

    /// Shown when a room's messages turned out to be from another app version after joining.
    static let versionMismatchTitle = "That room uses another version of Cravage"
    static let versionMismatchDetail = "This phone left the room. Update Cravage on both phones, then try again."

    static func buttonTitle(for room: RoomAdvert?) -> String {
        room.map { "Join \($0.label)" } ?? "Pick a room to join"
    }

    /// The host's name is what the room advertised, unchecked until the room code is compared;
    /// the second sentence is the confirmation barrier.
    static func note(for room: RoomAdvert?) -> String? {
        room.map { "Hosted by \($0.hostNickname). Everyone compares a room code before your figure is asked for." }
    }
}
