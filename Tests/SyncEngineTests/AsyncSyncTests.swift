import XCTest
@testable import SyncEngine

/// Thread-safe recorder for values captured inside `@Sendable` closures.
private final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

final class AsyncSyncTests: XCTestCase {
    func testAsyncSyncPushesAndPulls() async throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "local-1", data: ["k": "v"], status: .pending))

        let result = try await engine.sync(
            push: { records in
                try await Task.sleep(for: .milliseconds(1))
                return records.map { $0.withStatus(.synced) }
            },
            pull: {
                try await Task.sleep(for: .milliseconds(1))
                return [SyncRecord(id: "remote-1", data: ["r": "1"], status: .synced)]
            }
        )

        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(result.pulled, 1)
        XCTAssertEqual(engine.localStore.count, 2)
        XCTAssertEqual(engine.localStore.get("local-1")?.status, .synced)
    }

    func testAsyncSyncReportsProgress() async throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", status: .pending))
        let progress = Recorder<Int>()

        let result = try await engine.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [SyncRecord(id: "r1", status: .synced)] },
            onProgress: { current, _ in progress.append(current) }
        )

        XCTAssertEqual(progress.values, [1, 2])
        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(result.pulled, 1)
    }

    func testAsyncSyncQueuesOnPushFailure() async throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", status: .pending))

        let result = try await engine.sync(
            push: { _ in throw NSError(domain: "test", code: 1) },
            pull: { [] }
        )

        XCTAssertEqual(result.pushed, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(engine.retryQueue.count, 1)
    }

    func testAsyncSyncResolvesConflicts() async throws {
        let engine = SyncEngine(resolver: ConflictResolver(strategy: .remoteWins))
        let now = Date()
        engine.localStore.put(SyncRecord(id: "1", data: ["v": "local"], status: .modified, updatedAt: now))

        let result = try await engine.sync(
            push: { _ in [] },
            pull: { [SyncRecord(id: "1", data: ["v": "remote"], status: .synced, updatedAt: now.addingTimeInterval(1))] }
        )

        XCTAssertEqual(result.conflicts, 1)
        XCTAssertEqual(engine.localStore.get("1")?.data["v"], "remote")
    }

    func testAsyncSyncPropagatesPullErrors() async {
        let engine = SyncEngine()

        do {
            _ = try await engine.sync(push: { _ in [] }, pull: { throw NSError(domain: "test", code: 7) })
            XCTFail("Expected the pull error to propagate")
        } catch {
            XCTAssertEqual((error as NSError).code, 7)
        }
        XCTAssertFalse(engine.isSyncing)
    }

    func testAsyncSyncRefusesOverlappingSync() async throws {
        let engine = SyncEngine()
        let errors = Recorder<SyncError>()

        _ = try await engine.sync(
            push: { _ in [] },
            pull: {
                do {
                    _ = try engine.sync(push: { _ in [] }, pull: { [] })
                } catch let error as SyncError {
                    errors.append(error)
                }
                return []
            }
        )

        XCTAssertEqual(errors.values, [.syncInProgress])
    }

    func testAsyncSyncRecordsLastResult() async throws {
        let engine = SyncEngine()
        XCTAssertNil(engine.lastSyncResult)

        _ = try await engine.sync(push: { _ in [] }, pull: { [] })

        XCTAssertNotNil(engine.lastSyncResult)
    }
}
