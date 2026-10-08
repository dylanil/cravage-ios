import XCTest
@testable import CravageCore
@testable import Cravage

/// The share sheet is handed a file, not bare data: Gmail and other apps from outside Apple drop
/// bare data and open an empty draft. The file exists only from the share to leaving the result,
/// and only while this phone still sees the round agreed.
@MainActor
final class TranscriptExportTests: XCTestCase {
    private var lease = UUID()
    private var stars: [FakeStar] = []

    override func setUp() {
        super.setUp()
        lease = TranscriptExport.open()
    }

    override func tearDown() {
        TranscriptExport.close()
        for star in stars { star.coordinators.forEach { $0.leave() } }
        stars = []
        super.tearDown()
    }

    func testSharingWritesTheVerifiedTranscriptAsAJSONFile() async throws {
        let host = try await agreedRound()
        let url = try offer(host).writeFile()
        XCTAssertEqual(url.lastPathComponent, "cravage-transcript.json")
        let written = try Data(contentsOf: url)
        XCTAssertEqual(written, try XCTUnwrap(Transcript.make(from: XCTUnwrap(host.live.record))).encoded())
        XCTAssertEqual(TranscriptVerifier.verify(written), [])
    }

    func testASecondShareDoesNotOverwriteTheFirst() async throws {
        let export = offer(try await agreedRound())
        let first = try export.writeFile()
        let second = try export.writeFile()
        XCTAssertNotEqual(first, second, "a second share must not overwrite a file another app is reading")
    }

    func testClosingTheResultRemovesEveryTranscript() async throws {
        let export = offer(try await agreedRound())
        let first = try export.writeFile()
        let second = try export.writeFile()
        TranscriptExport.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptExport.folder.path))
    }

    /// A share sheet can outlive the result screen (a restart offer replaces it). A destination
    /// picked after that must not leave a file behind with nothing left to delete it.
    func testNothingIsWrittenOnceTheResultHasClosed() async throws {
        let export = offer(try await agreedRound())
        TranscriptExport.close()
        XCTAssertThrowsError(try export.writeFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptExport.folder.path))
    }

    /// The share sheet keeps the item it was given. A signed conflicting confirmation that arrives
    /// after the Share row was tapped withdraws agreement, and a destination picked after that must
    /// not get a file that reads as agreed.
    func testALateDisputeStopsAShareAlreadyOffered() async throws {
        let host = try await agreedRound()
        let export = offer(host)
        let star = try XCTUnwrap(stars.last)
        let joiner = star.coordinators[1].engine
        let conflicting = Envelope.signed(action: .resultConfirm, session: try XCTUnwrap(joiner.session),
                                          rosterHash: joiner.roster?.rosterHash,
                                          party: try XCTUnwrap(joiner.myLetter).letter,
                                          content: String(repeating: "0", count: 64),
                                          key: try XCTUnwrap(joiner.signingKey)).encoded()
        star.enqueue(from: 1, to: .host, conflicting)
        star.flush()
        XCTAssertEqual(host.live.record?.outcome, .disputed(try XCTUnwrap(joiner.myLetter)))
        XCTAssertThrowsError(try export.writeFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptExport.folder.path))
    }

    /// Each result screen gets its own permission. Opening a later result must not revive a share
    /// offered by one that has closed, while the later result's own share still works.
    func testAShareFromAClosedResultStaysRefusedWhenAnotherResultOpens() async throws {
        let old = offer(try await agreedRound())
        TranscriptExport.close()
        let newer = try await agreedRound()
        lease = TranscriptExport.open()
        XCTAssertThrowsError(try old.writeFile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptExport.folder.path))
        let written = try Data(contentsOf: offer(newer).writeFile())
        XCTAssertEqual(TranscriptVerifier.verify(written), [])
    }

    private func offer(_ coordinator: RoundCoordinator) -> TranscriptExport {
        TranscriptExport(lease: lease, coordinator: coordinator)!
    }

    private func agreedRound() async throws -> RoundCoordinator {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        stars.append(star)
        let host = star.coordinators[0]
        await host.createRoom(label: "Round", size: 3, nickname: "Host")
        for index in 1...2 {
            star.coordinators[index].join(roomID: "room", nickname: "Person \(index)")
            star.flush()
        }
        for pending in host.engine.pendingJoiners {
            host.admit(pending.verifyingKey, generation: host.engine.generation)
        }
        host.start(generation: host.engine.generation)
        star.flush()
        for phone in star.coordinators { RoundActions(phone).confirmRoomCode() }
        star.flush()
        for phone in star.coordinators { RoundActions(phone).submitFigure("10") }
        star.flush()
        XCTAssertNotNil(host.live.record.flatMap(Transcript.make(from:)))
        return host
    }
}
