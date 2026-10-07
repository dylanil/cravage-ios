import XCTest
@testable import CravageCore
@testable import Cravage

/// The share sheet is handed a file, not bare data: Gmail and other apps from outside Apple drop
/// bare data and open an empty draft. The file exists only from the share to leaving the result.
@MainActor
final class TranscriptExportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TranscriptExport.open()
    }

    override func tearDown() {
        TranscriptExport.close()
        super.tearDown()
    }

    func testSharingWritesTheVerifiedTranscriptAsAJSONFile() async throws {
        let record = try await agreedRecord()
        let url = try TranscriptExport.writeFile(for: record)
        XCTAssertEqual(url.lastPathComponent, "cravage-transcript.json")
        let written = try Data(contentsOf: url)
        XCTAssertEqual(written, try XCTUnwrap(Transcript.make(from: record)).encoded())
        XCTAssertEqual(TranscriptVerifier.verify(written), [])
    }

    func testASecondShareDoesNotOverwriteTheFirst() async throws {
        let record = try await agreedRecord()
        let first = try TranscriptExport.writeFile(for: record)
        let second = try TranscriptExport.writeFile(for: record)
        XCTAssertNotEqual(first, second, "a second share must not overwrite a file another app is reading")
    }

    func testClosingTheResultRemovesEveryTranscript() async throws {
        let record = try await agreedRecord()
        let first = try TranscriptExport.writeFile(for: record)
        let second = try TranscriptExport.writeFile(for: record)
        TranscriptExport.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptExport.folder.path))
    }

    /// A share sheet can outlive the result screen (a restart offer replaces it). A destination
    /// picked after that must not leave a file behind with nothing left to delete it.
    func testNothingIsWrittenOnceTheResultHasClosed() async throws {
        let record = try await agreedRecord()
        TranscriptExport.close()
        XCTAssertThrowsError(try TranscriptExport.writeFile(for: record))
        XCTAssertFalse(FileManager.default.fileExists(atPath: TranscriptExport.folder.path))
    }

    private func agreedRecord() async throws -> RoundRecord {
        let star = FakeStar(phones: 3, entitlement: FakeEntitlement(unlocked: false))
        defer { star.coordinators.forEach { $0.leave() } }
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
        return try XCTUnwrap(host.engine.record)
    }
}
