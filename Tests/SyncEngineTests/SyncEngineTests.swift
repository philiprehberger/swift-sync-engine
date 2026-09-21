import XCTest
@testable import SyncEngine

final class SyncEngineTests: XCTestCase {
    func testSyncPushesAndPulls() throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "local-1", data: ["k": "v"], status: .pending))

        let result = try engine.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [SyncRecord(id: "remote-1", data: ["r": "1"], status: .synced)] }
        )

        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(result.pulled, 1)
        XCTAssertEqual(engine.localStore.count, 2)
    }

    func testSyncResolvesConflicts() throws {
        let engine = SyncEngine(resolver: ConflictResolver(strategy: .remoteWins))
        let now = Date()
        engine.localStore.put(SyncRecord(id: "1", data: ["v": "local"], status: .modified, updatedAt: now))

        let result = try engine.sync(
            push: { _ in [] },
            pull: { [SyncRecord(id: "1", data: ["v": "remote"], status: .synced, updatedAt: now.addingTimeInterval(1))] }
        )

        XCTAssertEqual(result.conflicts, 1)
        XCTAssertEqual(engine.localStore.get("1")?.data["v"], "remote")
    }

    func testSyncQueuesOnPushFailure() throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", status: .pending))

        let result = try engine.sync(
            push: { _ in throw NSError(domain: "test", code: 1) },
            pull: { [] }
        )

        XCTAssertEqual(result.pushed, 0)
        XCTAssertEqual(engine.retryQueue.count, 1)
    }

    func testIsSyncing() throws {
        let engine = SyncEngine()
        XCTAssertFalse(engine.isSyncing)

        _ = try engine.sync(push: { _ in [] }, pull: { [] })
        XCTAssertFalse(engine.isSyncing) // should be false after sync completes
    }

    func testSyncResultTotal() {
        let result = SyncResult(pushed: 2, pulled: 3, conflicts: 1, retried: 1)
        XCTAssertEqual(result.total, 7)
    }

    func testLastSyncResult() throws {
        let engine = SyncEngine()
        XCTAssertNil(engine.lastSyncResult)
        _ = try engine.sync(push: { _ in [] }, pull: { [] })
        XCTAssertNotNil(engine.lastSyncResult)
    }

    func testSyncWithProgress() throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", status: .pending))

        var progressCalls: [(Int, Int)] = []
        let result = try engine.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [SyncRecord(id: "r1", status: .synced)] },
            onProgress: { current, total in
                progressCalls.append((current, total))
            }
        )

        XCTAssertFalse(progressCalls.isEmpty)
        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(result.pulled, 1)
    }

    func testRecordPendingAndQueuedIsPushedOnce() throws {
        let engine = SyncEngine(queue: RetryQueue(maxAttempts: 5, baseDelay: 0))
        engine.localStore.put(SyncRecord(id: "1", status: .pending))
        engine.retryQueue.enqueue(SyncRecord(id: "1", status: .pending))

        var batches: [[String]] = []
        _ = try engine.sync(
            push: { records in
                batches.append(records.map(\.id))
                return records.map { $0.withStatus(.synced) }
            },
            pull: { [] }
        )

        // One batch containing the record once — not a pending push plus a retry push
        XCTAssertEqual(batches, [["1"]])
    }

    func testSuccessfulPushClearsRetryQueue() throws {
        let engine = SyncEngine(queue: RetryQueue(maxAttempts: 5, baseDelay: 0))
        engine.localStore.put(SyncRecord(id: "1", status: .pending))
        engine.retryQueue.enqueue(SyncRecord(id: "1", status: .pending))
        XCTAssertEqual(engine.retryQueue.count, 1)

        _ = try engine.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [] }
        )

        XCTAssertEqual(engine.retryQueue.count, 0)
        XCTAssertEqual(engine.retryQueue.attempts(for: "1"), 0)
    }

    func testFailedCountReportsQueuedRecords() throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", status: .pending))
        engine.localStore.put(SyncRecord(id: "2", status: .pending))

        let result = try engine.sync(
            push: { _ in throw NSError(domain: "test", code: 1) },
            pull: { [] }
        )

        XCTAssertEqual(result.pushed, 0)
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(result.dropped, 0)
    }

    func testDroppedCountReportsAbandonedRecords() throws {
        let engine = SyncEngine(queue: RetryQueue(maxAttempts: 1))
        engine.localStore.put(SyncRecord(id: "1", status: .pending))

        let result = try engine.sync(
            push: { _ in throw NSError(domain: "test", code: 1) },
            pull: { [] }
        )

        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.dropped, 1)
        XCTAssertEqual(engine.retryQueue.count, 0)
    }

    func testConcurrentSyncIsRefused() throws {
        let engine = SyncEngine()
        var nested: Error?

        _ = try engine.sync(
            push: { _ in [] },
            pull: {
                do {
                    _ = try engine.sync(push: { _ in [] }, pull: { [] })
                } catch {
                    nested = error
                }
                return []
            }
        )

        XCTAssertEqual(nested as? SyncError, .syncInProgress)
    }

    func testIsSyncingIsTrueDuringSync() throws {
        let engine = SyncEngine()
        var observed = false

        _ = try engine.sync(
            push: { _ in [] },
            pull: {
                observed = engine.isSyncing
                return []
            }
        )

        XCTAssertTrue(observed)
        XCTAssertFalse(engine.isSyncing)
    }

    func testIsSyncingIsClearedAfterAThrownPull() {
        let engine = SyncEngine()
        XCTAssertThrowsError(
            try engine.sync(push: { _ in [] }, pull: { throw NSError(domain: "test", code: 1) })
        )
        XCTAssertFalse(engine.isSyncing)
    }

    func testDueRetriesArePushedWhenNotPending() throws {
        let engine = SyncEngine(queue: RetryQueue(maxAttempts: 5, baseDelay: 0))
        engine.retryQueue.enqueue(SyncRecord(id: "queued", status: .pending))

        let result = try engine.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [] }
        )

        XCTAssertEqual(result.retried, 1)
        XCTAssertEqual(engine.retryQueue.count, 0)
    }

    func testRetriesWaitForBackoff() throws {
        let engine = SyncEngine(queue: RetryQueue(maxAttempts: 5, baseDelay: 60))
        engine.retryQueue.enqueue(SyncRecord(id: "queued", status: .pending))

        let result = try engine.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [] }
        )

        XCTAssertEqual(result.retried, 0)
        XCTAssertEqual(engine.retryQueue.count, 1)  // still waiting out its backoff
    }
}
