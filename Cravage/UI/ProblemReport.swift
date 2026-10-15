import Foundation

/// Report a problem (Settings): an email to support with the diagnostics filled in.
///
/// Nothing leaves the phone until the person sends the email from their own email app, so the
/// report holds only what Copy diagnostics would copy, plus a line asking what happened. Apple's
/// header for `MFMailComposeViewController.canSendMail` names the two options when Mail cannot
/// send: tell the person, or open a "mailto" link. The link comes first, since it opens whichever
/// email app the phone uses; if nothing opens it, the diagnostics are copied and the screen says
/// where to send them.
struct ProblemReport: Equatable, Identifiable {
    /// The address docs/support.md and the privacy policy publish (Tools/check_store_paperwork.sh).
    static let address = "cravage.support@gmail.com"

    enum Outcome: Equatable { case compose, openedMailLink, copied }

    let diagnostics: String
    let subject: String
    let body: String
    var id: String { body }

    init(diagnostics: String, appVersion: String, build: String) {
        self.diagnostics = diagnostics
        subject = "Cravage problem report (\(appVersion), build \(build))"
        body = "What happened? Please describe it here.\n\n\n\n"
            + "Diagnostics from Cravage. They contain no figures, names or room names. "
            + "You can delete anything before you send.\n\n"
            + diagnostics
    }

    /// Every character outside the unreserved set is escaped: some mail apps read a bare "+" as a
    /// space, and a bare "&" would start another field.
    var mailLink: URL? {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func escaped(_ text: String) -> String? { text.addingPercentEncoding(withAllowedCharacters: unreserved) }
        guard let subject = escaped(subject), let body = escaped(body) else { return nil }
        return URL(string: "mailto:\(Self.address)?subject=\(subject)&body=\(body)")
    }

    /// Picks the way out. `.compose` asks the caller to show Apple's Mail screen with this report.
    @MainActor
    func send(canSendMail: Bool, open: (URL) async -> Bool, copy: (String) -> Void) async -> Outcome {
        if canSendMail { return .compose }
        if let link = mailLink, await open(link) { return .openedMailLink }
        copy(diagnostics)
        return .copied
    }
}
