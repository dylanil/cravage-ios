import XCTest
@testable import Cravage

/// Report a problem: an email to support with the diagnostics filled in, which the person sends
/// themselves. Apple's Mail screen when Mail can send; otherwise a mail link, which opens whichever
/// email app the phone uses; if nothing opens it, the diagnostics are copied so they can be pasted.
@MainActor
final class ProblemReportTests: XCTestCase {
    private let diagnostics = "Cravage diagnostics\napp: 1.0 (2)\nphase: idle"

    private func report(_ diagnostics: String? = nil) -> ProblemReport {
        ProblemReport(diagnostics: diagnostics ?? self.diagnostics, appVersion: "1.0", build: "2")
    }

    /// The address the support page and the privacy policy publish (checked against them by
    /// Tools/check_store_paperwork.sh).
    func testTheReportIsAddressedToSupport() throws {
        XCTAssertEqual(ProblemReport.address, "cravage.support@gmail.com")
        let link = try XCTUnwrap(report().mailLink)
        XCTAssertEqual(link.scheme, "mailto")
        XCTAssertEqual(URLComponents(url: link, resolvingAgainstBaseURL: false)?.path, ProblemReport.address)
    }

    func testTheReportCarriesTheDiagnosticsAndTheVersion() {
        let report = report()
        XCTAssertTrue(report.body.hasSuffix(diagnostics), report.body)
        XCTAssertTrue(report.subject.contains("1.0"), report.subject)
        XCTAssertTrue(report.subject.contains("build 2"), report.subject)
    }

    /// Characters a mail link gives meaning to arrive as written: a "+" read as a space, or an "&"
    /// read as the start of another field, would cut or change the diagnostics.
    func testTheMailLinkCarriesTheSameSubjectAndBody() throws {
        let awkward = "a+b & c=d ? e # f % g\nline two; 50%"
        let report = report(awkward)
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(report.mailLink), resolvingAgainstBaseURL: false))
        let fields = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(fields.count, 2, "\(fields)")
        XCTAssertEqual(fields["subject"], report.subject)
        XCTAssertEqual(fields["body"], report.body)
        XCTAssertFalse(parts.percentEncodedQuery?.contains("+") ?? true, "a literal + reads as a space in some mail apps")
    }

    func testWithMailSetUpTheMailScreenOpensAndNothingElseHappens() async {
        var opened: [URL] = []
        var copied: [String] = []
        let outcome = await report().send(canSendMail: true,
                                          open: { opened.append($0); return true },
                                          copy: { copied.append($0) })
        XCTAssertEqual(outcome, .compose)
        XCTAssertEqual(opened, [])
        XCTAssertEqual(copied, [])
    }

    func testWithoutMailTheMailLinkOpensInsteadOfNothing() async throws {
        var opened: [URL] = []
        var copied: [String] = []
        let report = report()
        let outcome = await report.send(canSendMail: false,
                                        open: { opened.append($0); return true },
                                        copy: { copied.append($0) })
        XCTAssertEqual(outcome, .openedMailLink)
        XCTAssertEqual(opened, [try XCTUnwrap(report.mailLink)])
        XCTAssertEqual(copied, [], "the email carries the diagnostics; the clipboard is left alone")
    }

    func testWhenNothingOpensTheLinkTheDiagnosticsAreCopied() async {
        var copied: [String] = []
        let outcome = await report().send(canSendMail: false, open: { _ in false }, copy: { copied.append($0) })
        XCTAssertEqual(outcome, .copied)
        XCTAssertEqual(copied, [diagnostics])
    }
}
