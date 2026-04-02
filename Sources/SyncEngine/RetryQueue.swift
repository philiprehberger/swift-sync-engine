import Foundation

/// An item in the retry queue.
public struct RetryItem: Sendable {
    public let record: SyncRecord
    public var attempts: Int
    public let enqueuedAt: Date

    public init(record: SyncRecord, attempts: Int = 0) {
        self.record = record
        self.attempts = attempts
        self.enqueuedAt = Date()
    }
}

/// Thread-safe queue for failed sync operations that should be retried.
public final class RetryQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RetryItem] = []

    /// Maximum retry attempts before an item is dropped.
    public let maxAttempts: Int

    public init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    /// Add a record to the retry queue.
    public func enqueue(_ record: SyncRecord) {
        lock.lock()
        if let idx = items.firstIndex(where: { $0.record.id == record.id }) {
            items[idx].attempts += 1
            if items[idx].attempts >= maxAttempts {
                items.remove(at: idx)
            }
        } else {
            items.append(RetryItem(record: record, attempts: 1))
        }
        lock.unlock()
    }

    /// Remove and return all items from the queue.
    public func dequeueAll() -> [SyncRecord] {
        lock.lock()
        let records = items.map(\.record)
        items.removeAll()
        lock.unlock()
        return records
    }

    /// Peek at all queued items without removing them.
    public func pending() -> [RetryItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    /// Number of items in the queue.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    /// Clear the queue.
    public func clear() {
        lock.lock()
        items.removeAll()
        lock.unlock()
    }
}
