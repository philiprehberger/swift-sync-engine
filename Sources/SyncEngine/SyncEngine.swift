import Foundation

/// Offline-first data sync engine with conflict resolution and retry support.
public final class SyncEngine: @unchecked Sendable {
    private let store: LocalStore
    private let queue: RetryQueue
    private let resolver: ConflictResolver
    private let lock = NSLock()
    private var _isSyncing = false

    /// The result of the most recent sync operation.
    public private(set) var lastSyncResult: SyncResult?

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

        let result = SyncResult(pushed: pushed, pulled: pulled, conflicts: conflicts, retried: retried)
        lock.lock()
        lastSyncResult = result
        lock.unlock()
        return result
    }

    /// Perform a sync cycle with progress reporting.
    ///
    /// - Parameters:
    ///   - push: Closure that sends local changes to remote.
    ///   - pull: Closure that fetches remote changes.
    ///   - onProgress: Called with (processed, total) counts during sync.
    /// - Returns: A SyncResult summarizing the operation.
    public func sync(
        push: ([SyncRecord]) throws -> [SyncRecord],
        pull: () throws -> [SyncRecord],
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> SyncResult {
        lock.lock()
        _isSyncing = true
        lock.unlock()

        defer {
            lock.lock()
            _isSyncing = false
            lock.unlock()
        }

        let pending = store.pending()
        let retryItems = queue.dequeueAll()
        let totalEstimate = pending.count + retryItems.count + 1 // +1 for pull
        var processed = 0
        var pushed = 0

        // Push pending
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
            processed += pending.count
            onProgress?(processed, totalEstimate)
        }

        // Retry queued
        var retried = 0
        if !retryItems.isEmpty {
            do {
                let responses = try push(retryItems)
                for record in responses {
                    store.markSynced(record.id)
                }
                retried = responses.count
            } catch {
                for item in retryItems {
                    queue.enqueue(item)
                }
            }
            processed += retryItems.count
            onProgress?(processed, totalEstimate)
        }

        // Pull
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
        processed += 1
        onProgress?(processed, totalEstimate)

        let result = SyncResult(pushed: pushed, pulled: pulled, conflicts: conflicts, retried: retried)
        lock.lock()
        lastSyncResult = result
        lock.unlock()
        return result
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
