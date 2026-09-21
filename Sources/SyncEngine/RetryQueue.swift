import Foundation

/// An item in the retry queue.
public struct RetryItem: Sendable {
    public let record: SyncRecord
    public var attempts: Int
    public let enqueuedAt: Date

    /// The earliest time this item should be retried — `enqueuedAt` plus the backoff for its
    /// attempt count.
    public let nextAttemptAt: Date

    public init(record: SyncRecord, attempts: Int = 0, backoff: TimeInterval = 0) {
        let now = Date()
        self.record = record
        self.attempts = attempts
        self.enqueuedAt = now
        self.nextAttemptAt = now.addingTimeInterval(backoff)
    }

    /// Whether the item's backoff has elapsed.
    public func isReady(at date: Date = Date()) -> Bool {
        nextAttemptAt <= date
    }
}

/// Thread-safe queue for failed sync operations that should be retried.
///
/// Attempt counts are tracked per record id and survive dequeuing, so a record that keeps
/// failing is dropped once it reaches `maxAttempts` instead of being retried forever. Each
/// attempt waits an exponentially growing backoff before the record becomes eligible again.
public final class RetryQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RetryItem] = []

    /// Failed attempts by record id, kept across dequeues so `maxAttempts` is enforced across
    /// sync cycles rather than restarting at 1 every time the queue is drained.
    private var attemptsByID: [String: Int] = [:]
    private var _droppedCount = 0

    /// Maximum retry attempts before an item is dropped.
    public let maxAttempts: Int

    /// Delay before the first retry. Each further attempt doubles it.
    public let baseDelay: TimeInterval

    /// Upper bound on the backoff delay.
    public let maxDelay: TimeInterval

    /// Create a retry queue.
    ///
    /// - Parameters:
    ///   - maxAttempts: Attempts before a record is abandoned.
    ///   - baseDelay: Delay before the first retry, in seconds. `0` retries immediately.
    ///   - maxDelay: Cap on the exponential backoff, in seconds.
    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1, maxDelay: TimeInterval = 300) {
        self.maxAttempts = maxAttempts
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(0, maxDelay)
    }

    /// Add a record to the retry queue, or record another failed attempt for one already queued.
    ///
    /// - Parameter record: The record whose push failed.
    /// - Returns: `true` if the record is queued for another attempt, `false` if it was dropped
    ///            for exhausting `maxAttempts`.
    @discardableResult
    public func enqueue(_ record: SyncRecord) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let attempts = (attemptsByID[record.id] ?? 0) + 1
        items.removeAll { $0.record.id == record.id }

        guard attempts < maxAttempts else {
            attemptsByID[record.id] = nil
            _droppedCount += 1
            return false
        }

        attemptsByID[record.id] = attempts
        items.append(RetryItem(record: record, attempts: attempts, backoff: backoff(for: attempts)))
        return true
    }

    /// Remove and return the records whose backoff has elapsed.
    ///
    /// - Parameter now: The reference time, injectable for testing.
    /// - Returns: The records that are due for another attempt.
    public func dequeueReady(now: Date = Date()) -> [SyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        let ready = items.filter { $0.isReady(at: now) }
        items.removeAll { $0.isReady(at: now) }
        return ready.map(\.record)
    }

    /// Remove and return all items from the queue, regardless of backoff.
    public func dequeueAll() -> [SyncRecord] {
        lock.lock()
        let records = items.map(\.record)
        items.removeAll()
        lock.unlock()
        return records
    }

    /// Forget a record that has since synced, clearing its queued item and attempt history.
    public func markSucceeded(_ id: String) {
        lock.lock()
        items.removeAll { $0.record.id == id }
        attemptsByID[id] = nil
        lock.unlock()
    }

    /// Peek at all queued items without removing them.
    public func pending() -> [RetryItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    /// Failed attempts recorded for a record id, including attempts already dequeued.
    public func attempts(for id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return attemptsByID[id] ?? 0
    }

    /// Number of items in the queue.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    /// Number of records abandoned for exhausting `maxAttempts`.
    public var droppedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _droppedCount
    }

    /// Clear the queue, its attempt history, and the dropped counter.
    public func clear() {
        lock.lock()
        items.removeAll()
        attemptsByID.removeAll()
        _droppedCount = 0
        lock.unlock()
    }

    /// Exponential backoff for an attempt: `baseDelay * 2^(attempts - 1)`, capped at `maxDelay`.
    private func backoff(for attempts: Int) -> TimeInterval {
        guard baseDelay > 0 else { return 0 }
        let exponent = Double(max(0, attempts - 1))
        return min(baseDelay * pow(2, exponent), maxDelay)
    }
}
