/// Text-only editing; the core remains the only parser and never receives a floating-point value.
enum FigureEditing {
    static func changingSign(_ text: String) -> String {
        if text.hasPrefix("-") { return String(text.dropFirst()) }
        return "-" + (text.hasPrefix("+") ? String(text.dropFirst()) : text)
    }

    static func appendingDecimalPoint(_ text: String) -> String {
        guard !text.contains("."), !text.contains(",") else { return text }
        return text + "."
    }
}
