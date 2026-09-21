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
    /// - Throws: `SyncError.syncInProgress` if another sync is running, or any error thrown by `pull`.
    public func sync(
        push: ([SyncRecord]) throws -> [SyncRecord],
        pull: () throws -> [SyncRecord]
    ) throws -> SyncResult {
        try sync(push: push, pull: pull, onProgress: nil)
    }

    /// Perform a sync cycle with progress reporting.
    ///
    /// Pending local records are pushed first, then any retry-queue records whose backoff has
    /// elapsed and that are not already in the pending batch, then remote changes are pulled.
    ///
    /// - Parameters:
    ///   - push: Closure that sends local changes to remote.
    ///   - pull: Closure that fetches remote changes.
    ///   - onProgress: Called with (processed, total) counts during sync.
    /// - Returns: A SyncResult summarizing the operation.
    /// - Throws: `SyncError.syncInProgress` if another sync is running, or any error thrown by `pull`.
    public func sync(
        push: ([SyncRecord]) throws -> [SyncRecord],
        pull: () throws -> [SyncRecord],
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> SyncResult {
        try beginSync()
        defer { endSync() }

        let plan = makePlan()
        var processed = 0
        var pushed = 0
        var retried = 0
        var failed = 0

        if !plan.pending.isEmpty {
            do {
                pushed = confirmPush(try push(plan.pending), for: plan.pending)
            } catch {
                failed += requeue(plan.pending)
            }
            processed += plan.pending.count
            onProgress?(processed, plan.totalEstimate)
        }

        if !plan.retries.isEmpty {
            do {
                retried = confirmPush(try push(plan.retries), for: plan.retries)
            } catch {
                failed += requeue(plan.retries)
            }
            processed += plan.retries.count
            onProgress?(processed, plan.totalEstimate)
        }

        let remoteRecords = try pull()
        let (pulled, conflicts) = applyPullResults(remoteRecords)
        processed += 1
        onProgress?(processed, plan.totalEstimate)

        return finish(
            plan: plan,
            pushed: pushed,
            pulled: pulled,
            conflicts: conflicts,
            retried: retried,
            failed: failed
        )
    }

    // MARK: - Shared cycle mechanics

    /// The batches a sync cycle will push, resolved before any I/O runs.
    struct SyncPlan {
        /// Records the local store has waiting to sync.
        let pending: [SyncRecord]
        /// Retry-queue records that are due and not already in `pending`.
        let retries: [SyncRecord]
        /// The queue's dropped counter when the cycle started, for per-cycle reporting.
        let droppedBefore: Int

        /// Units of work reported through `onProgress` — both batches plus the pull.
        var totalEstimate: Int { pending.count + retries.count + 1 }
    }

    /// Choose this cycle's batches.
    ///
    /// A record that failed earlier is still `.pending` in the store *and* sits in the retry
    /// queue, so the retry batch drops anything already in the pending batch — otherwise the
    /// same record is pushed twice in one cycle.
    func makePlan() -> SyncPlan {
        let pending = store.pending()
        let pendingIDs = Set(pending.map(\.id))
        let retries = queue.dequeueReady().filter { !pendingIDs.contains($0.id) }
        return SyncPlan(pending: pending, retries: retries, droppedBefore: queue.droppedCount)
    }

    /// Apply a successful push response, returning how many records it confirmed.
    ///
    /// Confirmed deletions clear their tombstone locally; everything else is marked synced.
    /// Either way the record is cleared from the retry queue so a stale entry cannot re-push
    /// a record that has already synced.
    func confirmPush(_ responses: [SyncRecord], for batch: [SyncRecord]) -> Int {
        let deletedIDs = Set(batch.filter { $0.status == .deleted }.map(\.id))
        for record in responses {
            if deletedIDs.contains(record.id) {
                store.remove(record.id)
            } else {
                store.markSynced(record.id)
            }
            queue.markSucceeded(record.id)
        }
        return responses.count
    }

    /// Queue a failed batch for another attempt, returning how many records failed.
    func requeue(_ batch: [SyncRecord]) -> Int {
        for record in batch {
            queue.enqueue(record)
        }
        return batch.count
    }

    /// Apply pulled remote records: propagate deletions, resolve conflicts, and store the rest.
    ///
    /// - Returns: The number of records pulled and the number of conflicts resolved.
    func applyPullResults(_ remoteRecords: [SyncRecord]) -> (pulled: Int, conflicts: Int) {
        var pulled = 0
        var conflicts = 0

        for remote in remoteRecords {
            if remote.status == .deleted {
                store.remove(remote.id)
                pulled += 1
                continue
            }

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

        return (pulled, conflicts)
    }

    /// Assemble and record the cycle's result.
    func finish(
        plan: SyncPlan,
        pushed: Int,
        pulled: Int,
        conflicts: Int,
        retried: Int,
        failed: Int
    ) -> SyncResult {
        let result = SyncResult(
            pushed: pushed,
            pulled: pulled,
            conflicts: conflicts,
            retried: retried,
            failed: failed,
            dropped: max(0, queue.droppedCount - plan.droppedBefore)
        )
        lock.lock()
        lastSyncResult = result
        lock.unlock()
        return result
    }

    /// Claim the engine for a sync cycle.
    ///
    /// - Throws: `SyncError.syncInProgress` if another sync is already running.
    func beginSync() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !_isSyncing else { throw SyncError.syncInProgress }
        _isSyncing = true
    }

    /// Release the engine at the end of a sync cycle.
    func endSync() {
        lock.lock()
        _isSyncing = false
        lock.unlock()
    }
}
