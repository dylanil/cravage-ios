import Foundation

/// Report a problem (Settings): an email to support with the diagnostics filled in.
///
/// Nothing reaches support until the person sends the email (a draft they save can still sync to
/// their own mail provider), so the report holds only what Copy diagnostics would copy, plus a
/// line asking what happened. Apple's header for `MFMailComposeViewController.canSendMail` names
/// two options when Mail cannot send: tell the person, or open a "mailto" link. Cravage tells the
/// person: a mailto link can land in a Mail app with no account and lose the report without a word
/// (review of 6f7f6c1), so the message gives the address and copies the diagnostics only when the
/// person asks (owner decision 2026-10-15).
struct ProblemReport: Equatable, Identifiable {
    /// The address docs/support.md and the privacy policy publish (Tools/check_store_paperwork.sh).
    static let address = "cravage.support@gmail.com"

    static let noMailTitle = "Mail isn't set up on this iPhone"
    static let noMailMessage = "Copy the diagnostics, then email them to \(address) from any email app."

    enum Way: Equatable { case mailScreen, copyAndEmail }

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

    /// Apple's email screen when Mail can send; otherwise the message with the address.
    static func way(canSendMail: Bool) -> Way {
        canSendMail ? .mailScreen : .copyAndEmail
    }
}
