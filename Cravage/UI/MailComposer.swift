import MessageUI
import SwiftUI

/// Apple's Mail screen with a problem report filled in. Shown only when
/// `MFMailComposeViewController.canSendMail()` says Mail is set up; the person sends, edits or
/// cancels it there, and `finished` gets Apple's result.
struct MailComposer: UIViewControllerRepresentable {
    let report: ProblemReport
    let finished: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([ProblemReport.address])
        mail.setSubject(report.subject)
        mail.setMessageBody(report.body, isHTML: false)
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    /// MessageUI's header does not say which thread calls the delegate. The conformance is
    /// main-actor isolated, so Swift checks at run time that the call arrives on the main actor
    /// rather than assuming it before `finished` changes the screen's state.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let finished: (MFMailComposeResult) -> Void

        init(finished: @escaping (MFMailComposeResult) -> Void) {
            self.finished = finished
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            finished(result)
        }
    }
}
