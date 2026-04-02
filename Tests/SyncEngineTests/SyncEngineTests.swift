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
}
