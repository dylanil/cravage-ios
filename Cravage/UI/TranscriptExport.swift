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
/// moment a destination asks for it, and only while the result screen is open: closing it removes
/// every file and refuses later writes, since a share sheet can outlive the screen (a restart offer
/// replaces it). Writing and removing take turns under one lock. Launch removes anything a closed
/// app left behind.
struct TranscriptExport: Transferable {
    enum Failure: Error { case notExportable, resultClosed }

    /// Whether the result screen is open, and so whether a share may write.
    private static let isOpen = Mutex(false)

    let record: RoundRecord

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try writeFile(for: export.record))
        }
    }

    static var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "transcripts", directoryHint: .isDirectory)
    }

    /// Each share gets its own folder, so a second share never rewrites a file another app is still
    /// reading.
    static func writeFile(for record: RoundRecord) throws -> URL {
        guard let transcript = Transcript.make(from: record) else { throw Failure.notExportable }
        return try isOpen.withLock { open in
            guard open else { throw Failure.resultClosed }
            let directory = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "cravage-transcript.json")
            // Unless-open rather than complete: a share already reading the file survives a lock.
            try transcript.encoded().write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            return url
        }
    }

    static func open() {
        isOpen.withLock { $0 = true }
    }

    static func close() {
        isOpen.withLock { open in
            open = false
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
