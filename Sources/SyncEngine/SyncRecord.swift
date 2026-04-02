import Foundation

/// Sync status of a record.
public enum SyncStatus: String, Sendable, Codable {
    case pending
    case modified
    case synced
    case conflicted
    case deleted
}

/// A syncable data record with metadata for conflict resolution.
public struct SyncRecord: Sendable, Identifiable, Codable {
    public let id: String
    public var data: [String: String]
    public var status: SyncStatus
    public var updatedAt: Date
    public var version: Int

    public init(
        id: String,
        data: [String: String] = [:],
        status: SyncStatus = .pending,
        updatedAt: Date = Date(),
        version: Int = 1
    ) {
        self.id = id
        self.data = data
        self.status = status
        self.updatedAt = updatedAt
        self.version = version
    }

    /// Create a copy with a different status.
    public func withStatus(_ newStatus: SyncStatus) -> SyncRecord {
        var copy = self
        copy.status = newStatus
        return copy
    }

    /// Create a copy with incremented version.
    public func incrementVersion() -> SyncRecord {
        var copy = self
        copy.version += 1
        copy.updatedAt = Date()
        return copy
    }
}
