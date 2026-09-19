import Foundation
import Observation
import CravageCore

/// The only thing the app keeps between rounds: README's honesty copy promises that round history
/// is not saved and that the nickname is saved on this phone, so this store holds exactly that.
///
/// A nickname the roster would reject is never stored, so a name cannot be accepted here and then
/// fail at the point of joining a room.
@MainActor
@Observable
final class NicknameStore {
    private static let key = "nickname"
    private let defaults: UserDefaults
    private(set) var nickname: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.key) ?? ""
        self.nickname = RoomText.isValidNickname(saved) ? saved : ""
    }

    var hasNickname: Bool { !nickname.isEmpty }

    @discardableResult
    func save(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoomText.isValidNickname(trimmed) else { return false }
        nickname = trimmed
        defaults.set(trimmed, forKey: Self.key)
        return true
    }
}
