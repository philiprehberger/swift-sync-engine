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

    /// Total records processed.
    public var total: Int { pushed + pulled + conflicts + retried }

    public init(pushed: Int, pulled: Int, conflicts: Int, retried: Int) {
        self.pushed = pushed
        self.pulled = pulled
        self.conflicts = conflicts
        self.retried = retried
    }
}
