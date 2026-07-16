import XCTest
@testable import SyncEngine

final class DeletionTests: XCTestCase {
    func testDeleteMarksRecordDeleted() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", status: .synced))
        let existed = store.delete("1")
        XCTAssertTrue(existed)
        XCTAssertEqual(store.get("1")?.status, .deleted)
    }

    func testDeleteMissingReturnsFalse() {
        let store = LocalStore()
        XCTAssertFalse(store.delete("missing"))
    }

    func testDeletedRecordIsPending() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", status: .synced))
        store.delete("1")
        let pendingIDs = store.pending().map(\.id)
        XCTAssertEqual(pendingIDs, ["1"])
    }

    func testStatisticsCountsDeletedAndConflicted() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", status: .synced))
        store.put(SyncRecord(id: "2", status: .conflicted))
        store.delete("1")
        let stats = store.statistics
        XCTAssertEqual(stats.deleted, 1)
        XCTAssertEqual(stats.conflicted, 1)
    }

    func testPushRemovesTombstoneLocally() throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", status: .synced))
        engine.localStore.delete("1")

        // The push confirms the deletion by echoing the record back.
        let result = try engine.sync(
            push: { records in records },
            pull: { [] }
        )

        XCTAssertEqual(result.pushed, 1)
        XCTAssertNil(engine.localStore.get("1"), "confirmed deletion should clear the tombstone")
    }

    func testPullPropagatesRemoteDeletion() throws {
        let engine = SyncEngine()
        engine.localStore.put(SyncRecord(id: "1", data: ["a": "b"], status: .synced))

        let result = try engine.sync(
            push: { _ in [] },
            pull: { [SyncRecord(id: "1", status: .deleted)] }
        )

        XCTAssertEqual(result.pulled, 1)
        XCTAssertNil(engine.localStore.get("1"), "remote deletion should remove the local record")
    }
}
