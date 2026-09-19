import CravageCore

/// The wording on the figure screen. Kept apart from the view so the honesty lines can be pinned
/// by tests: the collusion sentence has to follow the actual room size, and the limit has to follow
/// the actual domain.
enum FigureCopy {
    /// The mockup says "use your decimal mark". The parser is an exact port of the web app's and
    /// takes an ASCII full stop only, so the line says so rather than inviting a comma that would
    /// be rejected - or, worse, read as something else. Raised with the owner.
    static let limit = "Up to 999,999,999,999.99. Use a full stop for the decimal point, and leave out thousands separators."

    /// SPEC's honesty rule: a round of N protects one figure from any single other party, and from
    /// nobody if the rest pool what they know.
    static func collusion(size: Int) -> String {
        let others = size - 1
        let they = others == 1 ? "the other person could" : "the other \(others) could"
        let sharing = others == 1 ? "" : " if they shared theirs with each other"
        return "With \(size) people, \(they) work out your figure\(sharing)."
    }

    /// Allowed honesty copy, unchanged from CLAUDE.md.
    static let onThisPhone = "Your figure is processed on your phone; the app sends a masked share to the other participants."
}
