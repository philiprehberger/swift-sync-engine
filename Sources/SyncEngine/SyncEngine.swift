import Foundation

/// Offline-first data sync engine with conflict resolution and retry support.
public final class SyncEngine: @unchecked Sendable {
    private let store: LocalStore
    private let queue: RetryQueue
    private let resolver: ConflictResolver
    private let lock = NSLock()
    private var _isSyncing = false

    /// Whether a sync is currently in progress.
    public var isSyncing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSyncing
    }

    /// Create a sync engine with the given components.
    public init(
        store: LocalStore = LocalStore(),
        queue: RetryQueue = RetryQueue(),
        resolver: ConflictResolver = ConflictResolver()
    ) {
        self.store = store
        self.queue = queue
        self.resolver = resolver
    }

    /// Access the local store.
    public var localStore: LocalStore { store }

    /// Access the retry queue.
    public var retryQueue: RetryQueue { queue }

    /// Access the conflict resolver.
    public var conflictResolver: ConflictResolver { resolver }

    /// Perform a sync cycle: push pending changes, pull remote changes, resolve conflicts.
    ///
    /// - Parameters:
    ///   - push: Closure that sends local changes to remote. Returns remote responses.
    ///   - pull: Closure that fetches remote changes. Returns remote records.
    /// - Returns: A SyncResult summarizing the operation.
    public func sync(
        push: ([SyncRecord]) throws -> [SyncRecord],
        pull: () throws -> [SyncRecord]
    ) throws -> SyncResult {
        lock.lock()
        _isSyncing = true
        lock.unlock()

        defer {
            lock.lock()
            _isSyncing = false
            lock.unlock()
        }

        // Push pending local changes
        let pending = store.pending()
        var pushed = 0
        if !pending.isEmpty {
            do {
                let responses = try push(pending)
                for record in responses {
                    store.markSynced(record.id)
                }
                pushed = responses.count
            } catch {
                for record in pending {
                    queue.enqueue(record)
                }
            }
        }

        // Retry queued items
        let retried = retryPending(push: push)

        // Pull remote changes
        let remoteRecords = try pull()
        var pulled = 0
        var conflicts = 0

        for remote in remoteRecords {
            if let local = store.get(remote.id) {
                if local.updatedAt != remote.updatedAt && local.status == .modified {
                    let resolved = resolver.resolve(local: local, remote: remote)
                    store.put(resolved)
                    conflicts += 1
                } else {
                    store.put(remote.withStatus(.synced))
                    pulled += 1
                }
            } else {
                store.put(remote.withStatus(.synced))
                pulled += 1
            }
        }

        return SyncResult(pushed: pushed, pulled: pulled, conflicts: conflicts, retried: retried)
    }

    private func retryPending(push: ([SyncRecord]) throws -> [SyncRecord]) -> Int {
        let items = queue.dequeueAll()
        guard !items.isEmpty else { return 0 }
        var retried = 0
        do {
            let responses = try push(items)
            for record in responses {
                store.markSynced(record.id)
            }
            retried = responses.count
        } catch {
            for item in items {
                queue.enqueue(item)
            }
        }
        return retried
    }
}
