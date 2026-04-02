import Foundation

/// Thread-safe in-memory store for local records.
public final class LocalStore: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: SyncRecord] = [:]

    public init() {}

    /// Store or update a record.
    public func put(_ record: SyncRecord) {
        lock.lock()
        records[record.id] = record
        lock.unlock()
    }

    /// Retrieve a record by ID.
    public func get(_ id: String) -> SyncRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[id]
    }

    /// Remove a record by ID.
    @discardableResult
    public func remove(_ id: String) -> SyncRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records.removeValue(forKey: id)
    }

    /// Get all records.
    public func all() -> [SyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records.values)
    }

    /// Get records with pending or modified status.
    public func pending() -> [SyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.status == .pending || $0.status == .modified }
    }

    /// Mark a record as synced.
    public func markSynced(_ id: String) {
        lock.lock()
        records[id]?.status = .synced
        lock.unlock()
    }

    /// Mark a record as modified (local change after sync).
    public func markModified(_ id: String) {
        lock.lock()
        records[id]?.status = .modified
        records[id]?.updatedAt = Date()
        lock.unlock()
    }

    /// Number of stored records.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }

    /// Remove all records.
    public func clear() {
        lock.lock()
        records.removeAll()
        lock.unlock()
    }

    /// Query records with a predicate.
    ///
    /// - Parameter predicate: Closure that returns true for matching records.
    /// - Returns: Array of matching records.
    public func query(where predicate: (SyncRecord) -> Bool) -> [SyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter(predicate)
    }

    /// Bulk insert an array of records.
    ///
    /// - Parameter items: The records to insert.
    public func putAll(_ items: [SyncRecord]) {
        lock.lock()
        for item in items {
            records[item.id] = item
        }
        lock.unlock()
    }

    /// Statistics about record statuses.
    public var statistics: (total: Int, pending: Int, synced: Int, modified: Int) {
        lock.lock()
        defer { lock.unlock() }
        let total = records.count
        let pending = records.values.filter { $0.status == .pending }.count
        let synced = records.values.filter { $0.status == .synced }.count
        let modified = records.values.filter { $0.status == .modified }.count
        return (total: total, pending: pending, synced: synced, modified: modified)
    }
}
