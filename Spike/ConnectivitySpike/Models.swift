import Foundation

// Throwaway wire format for the connectivity spike only - not the real protocol.
// The real app never sends anything like this (no crypto, no signatures, plain text).
struct SpikeMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case hello, admit, decline, chat
    }
    var kind: Kind
    var senderID: String
    var senderNickname: String
    var text: String
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let text: String

    var formatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return "[\(f.string(from: time))] \(text)"
    }
}

struct Peer: Identifiable, Sendable, Equatable {
    let id: String
    var nickname: String
    var admitted: Bool
}

enum SpikeRole {
    case host
    case join
}
