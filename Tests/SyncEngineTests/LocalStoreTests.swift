import XCTest
@testable import SyncEngine

final class LocalStoreTests: XCTestCase {
    func testPutAndGet() {
        let store = LocalStore()
        let record = SyncRecord(id: "1", data: ["name": "Alice"])
        store.put(record)
        XCTAssertEqual(store.get("1")?.data["name"], "Alice")
    }

    func testRemove() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1"))
        let removed = store.remove("1")
        XCTAssertNotNil(removed)
        XCTAssertNil(store.get("1"))
    }

    func testPending() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", status: .pending))
        store.put(SyncRecord(id: "2", status: .synced))
        store.put(SyncRecord(id: "3", status: .modified))
        XCTAssertEqual(store.pending().count, 2)
    }

    func testMarkSynced() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", status: .pending))
        store.markSynced("1")
        XCTAssertEqual(store.get("1")?.status, .synced)
    }

    func testMarkModified() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", status: .synced))
        store.markModified("1")
        XCTAssertEqual(store.get("1")?.status, .modified)
    }

    func testCount() {
        let store = LocalStore()
        store.put(SyncRecord(id: "a"))
        store.put(SyncRecord(id: "b"))
        XCTAssertEqual(store.count, 2)
    }

    func testClear() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1"))
        store.clear()
        XCTAssertEqual(store.count, 0)
    }
}
