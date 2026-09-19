import CravageCore

/// What the result screen says, kept apart from the view so the rules that matter can be tested.
///
/// Two of them are load-bearing. A relay can make two honest phones each name the other, so the
/// wording is always "did not agree with this phone" and never an accusation (SPEC section 3, copy
/// rule). And only a round this phone saw agreed can be exported: the transcript format has no way
/// to say a result was disputed, so a disputed or partial round is not written out at all.
enum OutcomeCopy {
    static func title(_ outcome: Outcome) -> String {
        switch outcome {
        case .agreed: return "Result"
        case .mismatch: return "Phones did not agree"
        case .partial: return "Result, not agreed"
        case .disputed: return "Result disputed"
        }
    }

    /// A mismatch means this phone cannot stand behind any number, so none is shown.
    static func showsAverage(_ outcome: Outcome) -> Bool {
        if case .mismatch = outcome { return false }
        return true
    }

    static func canExport(_ outcome: Outcome) -> Bool {
        if case .agreed = outcome { return true }
        return false
    }

    /// The sentence under the number. `name` turns a letter into the nickname on the roster.
    static func detail(_ outcome: Outcome, size: Int, name: (PartyLabel) -> String) -> String {
        switch outcome {
        case .agreed:
            return "All \(size) phones signed agreement to the same set of shares."
        case let .mismatch(letters):
            let who = list(letters.map(name))
            return "\(who) did not agree with this phone about the shares. "
                + "This does not mean \(list(letters.map(name), possessive: false)) did anything wrong. No average is shown."
        case let .partial(missing):
            let who = list(missing.map(name))
            return "\(who) didn't sign agreement in time. Treat this result with care. It can't be exported."
        case let .disputed(letter):
            return "After the result appeared, a conflicting agreement arrived from \(name(letter))'s phone. "
                + "A transcript you already shared is unchanged; this phone now marks the result disputed. "
                + "This round can't be exported again: the file has no way to say a result is disputed."
        }
    }

    /// "Alex's phone", "Alex's and Dee's phones".
    private static func list(_ names: [String], possessive: Bool = true) -> String {
        guard !names.isEmpty else { return possessive ? "Another phone" : "they" }
        guard possessive else {
            return names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
        let owned = names.map { "\($0)'s" }
        if owned.count == 1 { return "\(owned[0]) phone" }
        return owned.dropLast().joined(separator: ", ") + " and " + owned[owned.count - 1] + " phones"
    }
}
