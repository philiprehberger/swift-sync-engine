import Foundation

extension SyncEngine {
    /// Perform a sync cycle with `async` push and pull closures.
    ///
    /// The same cycle as the synchronous ``sync(push:pull:onProgress:)`` — pending records
    /// first, then due retries, then the pull — but the backend calls are awaited rather than
    /// blocking the calling thread, which is what a network-backed `push`/`pull` needs.
    ///
    /// ```swift
    /// let result = try await engine.sync(
    ///     push: { records in try await api.upload(records) },
    ///     pull: { try await api.fetchChanges() }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - push: Closure that sends local changes to remote. Returns remote responses.
    ///   - pull: Closure that fetches remote changes. Returns remote records.
    ///   - onProgress: Called with (processed, total) counts during sync.
    /// - Returns: A SyncResult summarizing the operation.
    /// - Throws: `SyncError.syncInProgress` if another sync is running, or any error thrown by `pull`.
    public func sync(
        push: @Sendable ([SyncRecord]) async throws -> [SyncRecord],
        pull: @Sendable () async throws -> [SyncRecord],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> SyncResult {
        try beginSync()
        defer { endSync() }

        let plan = makePlan()
        var processed = 0
        var pushed = 0
        var retried = 0
        var failed = 0

        if !plan.pending.isEmpty {
            do {
                pushed = confirmPush(try await push(plan.pending), for: plan.pending)
            } catch {
                failed += requeue(plan.pending)
            }
            processed += plan.pending.count
            onProgress?(processed, plan.totalEstimate)
        }

        if !plan.retries.isEmpty {
            do {
                retried = confirmPush(try await push(plan.retries), for: plan.retries)
            } catch {
                failed += requeue(plan.retries)
            }
            processed += plan.retries.count
            onProgress?(processed, plan.totalEstimate)
        }

        let remoteRecords = try await pull()
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
}
