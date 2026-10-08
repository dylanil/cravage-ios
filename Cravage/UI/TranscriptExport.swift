import Foundation
import Synchronization
import CoreTransferable
import UniformTypeIdentifiers
import CravageCore

/// The transcript, written only when the person picks somewhere to share it.
///
/// The screen says round history is not saved, so nothing is written until someone shares. The
/// share sheet gets a file rather than bare data, because Gmail and other apps from outside Apple
/// drop bare data and open an empty draft. The file is written at the
/// moment a destination asks for it, from the record as this phone holds it then, and only while
/// the result screen that offered the share is open. A share sheet can outlive the screen (a
/// restart offer replaces it) and keeps the item it was given, so a late conflicting confirmation
/// or a closed screen stops the write even after the item was handed over. Each result screen gets
/// its own lease, so opening another result never revives an older share. Closing removes every
/// file. Writing and removing take turns under one lock. Launch removes anything a closed app left
/// behind.
struct TranscriptExport: Transferable {
    enum Failure: Error { case notExportable, resultClosed }

    /// The lease of the result screen that is open, if any: the only one whose shares may write.
    private static let openLease = Mutex<UUID?>(nil)

    let lease: UUID
    /// The round this share was offered for. A record from any other round is refused.
    let session: String
    /// The record as the engine holds it when the file is asked for, not when Share was tapped.
    let current: @MainActor @Sendable () -> RoundRecord?

    @MainActor
    init?(lease: UUID, coordinator: RoundCoordinator) {
        guard let record = coordinator.live.record else { return nil }
        self.lease = lease
        self.session = record.boundSession
        self.current = { [coordinator] in coordinator.live.record }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try await export.writeFile())
        }
    }

    static var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "transcripts", directoryHint: .isDirectory)
    }

    /// Each share gets its own folder, so a second share never rewrites a file another app is still
    /// reading. On the main actor, so no message can change the record between the check and the
    /// write.
    @MainActor
    func writeFile() throws -> URL {
        guard let record = current(), record.boundSession == session,
              let transcript = Transcript.make(from: record) else { throw Failure.notExportable }
        return try Self.openLease.withLock { open in
            guard open == lease else { throw Failure.resultClosed }
            let directory = Self.folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "cravage-transcript.json")
            // Unless-open rather than complete: a share already reading the file survives a lock.
            try transcript.encoded().write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            return url
        }
    }

    /// Starts a new lease for a result screen that has just appeared, ending any earlier one.
    static func open() -> UUID {
        let lease = UUID()
        openLease.withLock { $0 = lease }
        return lease
    }

    static func close() {
        openLease.withLock { open in
            open = nil
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
