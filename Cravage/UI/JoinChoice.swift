import Foundation

/// Join, option B (decided 2026-10-04): the person picks a room, then joins it with one clear button.
/// Kept apart from the view so the rules are tested: a chosen room that stops advertising is no
/// longer chosen, and the note claims only what is true.
enum JoinChoice {
    /// The chosen room, if it is still in the list.
    static func chosen(_ id: String?, in rooms: [RoomAdvert]) -> RoomAdvert? {
        guard let id else { return nil }
        return rooms.first { $0.id == id }
    }

    static func buttonTitle(for room: RoomAdvert?) -> String {
        room.map { "Join \($0.label)" } ?? "Pick a room to join"
    }

    /// The host's name is what the room advertised, unchecked until the room code is compared;
    /// the second sentence is the confirmation barrier.
    static func note(for room: RoomAdvert?) -> String? {
        room.map { "Hosted by \($0.hostNickname). Everyone compares a room code before your figure is asked for." }
    }
}
