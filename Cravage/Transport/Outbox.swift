import Foundation

/// The ordered send queue for one connection. Bounded: a peer that stops reading cannot make the
/// phone buffer without limit, and an overflow is reported instead of silently dropping the oldest
/// envelope. Drainable: closing sends what is already queued (an abort, a decline) before the
/// connection goes, up to a time limit.
@MainActor
final class Outbox {
    static let capacity = 128

    private var queue: [Data] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var closing = false
    private(set) var failed = false
    private var task: Task<Void, Never>?
    /// Called once, on the main actor, when a send fails. The connection is then useless: everything
    /// still queued is gone, so the transport must close it and say so rather than wait for the next send
    /// to notice (device report 2026-10-04: a phone silently stopped receiving mid-round).
    var onFailure: (() -> Void)?

    init(send: @escaping @Sendable (Data) async throws -> Void) {
        task = Task { [weak self] in await self?.run(send) }
    }

    /// False when the queue is closed, has failed, or is full; the caller should drop the connection.
    func enqueue(_ data: Data) -> Bool {
        guard !closing, !failed, queue.count < Self.capacity else { return false }
        queue.append(data)
        wake()
        return true
    }

    /// Stops accepting new data; finishes when the queue is sent, a send fails, or `drainMs` passes.
    func close(drainMs: UInt64) async {
        closing = true
        wake()
        guard let task else { return }
        let timeout = Task {
            try? await Task.sleep(for: .milliseconds(Int64(drainMs)))
            task.cancel()
        }
        await task.value
        timeout.cancel()
    }

    private func wake() {
        waiter?.resume()
        waiter = nil
    }

    private func run(_ send: @Sendable (Data) async throws -> Void) async {
        while !Task.isCancelled {
            if queue.isEmpty {
                if closing { return }
                await withCheckedContinuation { waiter = $0 }
                continue
            }
            let next = queue.removeFirst()
            do {
                try await send(next)
            } catch {
                failed = true
                queue.removeAll()
                onFailure?()
                return
            }
        }
    }
}
