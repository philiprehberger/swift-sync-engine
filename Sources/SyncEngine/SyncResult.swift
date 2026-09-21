import Foundation

/// Summary of a sync operation.
public struct SyncResult: Sendable {
    /// Number of records pushed to remote.
    public let pushed: Int
    /// Number of records pulled from remote.
    public let pulled: Int
    /// Number of conflicts resolved.
    public let conflicts: Int
    /// Number of retried items from the queue.
    public let retried: Int
    /// Number of records whose push failed this cycle and were queued for retry.
    public let failed: Int
    /// Number of records abandoned this cycle for exhausting the retry queue's `maxAttempts`.
    public let dropped: Int

    /// Total records processed.
    public var total: Int { pushed + pulled + conflicts + retried }

    public init(
        pushed: Int,
        pulled: Int,
        conflicts: Int,
        retried: Int,
        failed: Int = 0,
        dropped: Int = 0
    ) {
        self.pushed = pushed
        self.pulled = pulled
        self.conflicts = conflicts
        self.retried = retried
        self.failed = failed
        self.dropped = dropped
    }
}
