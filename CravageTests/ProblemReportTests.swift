import XCTest
@testable import Cravage

/// Report a problem: an email to support with the diagnostics filled in, which the person sends
/// themselves from Apple's email screen inside Cravage. When Mail is not set up, Cravage shows the
/// address and a Copy diagnostics button instead of handing the report to another app (owner
/// decision 2026-10-15, after the review of 6f7f6c1).
@MainActor
final class ProblemReportTests: XCTestCase {
    private let diagnostics = "Cravage diagnostics\napp: 1.0 (2)\nphase: idle"

    private func report() -> ProblemReport {
        ProblemReport(diagnostics: diagnostics, appVersion: "1.0", build: "2")
    }

    /// The address the support page and the privacy policy publish (checked against them by
    /// Tools/check_store_paperwork.sh).
    func testTheReportIsAddressedToSupport() {
        XCTAssertEqual(ProblemReport.address, "cravage.support@gmail.com")
    }

    func testTheReportCarriesTheDiagnosticsAndTheVersion() {
        let report = report()
        XCTAssertTrue(report.body.hasSuffix(diagnostics), report.body)
        XCTAssertTrue(report.subject.contains("1.0"), report.subject)
        XCTAssertTrue(report.subject.contains("build 2"), report.subject)
    }

    func testWithMailSetUpTheMailScreenOpens() {
        XCTAssertEqual(ProblemReport.way(canSendMail: true), .mailScreen)
    }

    /// No other app is opened: one that cannot send would swallow the report without a word.
    func testWithoutMailCravageOffersToCopyTheDiagnosticsInstead() {
        XCTAssertEqual(ProblemReport.way(canSendMail: false), .copyAndEmail)
    }

    /// The message is the only place the person learns where to send what they copy.
    func testTheNoMailMessageGivesTheSupportAddress() {
        XCTAssertTrue(ProblemReport.noMailMessage.contains(ProblemReport.address), ProblemReport.noMailMessage)
    }
}
