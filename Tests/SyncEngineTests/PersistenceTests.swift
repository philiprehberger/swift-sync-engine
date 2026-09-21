import XCTest
@testable import SyncEngine

final class PersistenceTests: XCTestCase {
    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-engine-\(UUID().uuidString).json")
    }

    func testSnapshotReturnsEveryRecord() {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", data: ["a": "1"]))
        store.put(SyncRecord(id: "2", data: ["b": "2"]))

        XCTAssertEqual(Set(store.snapshot().map(\.id)), ["1", "2"])
    }

    func testRestoreReplacesContents() {
        let store = LocalStore()
        store.put(SyncRecord(id: "old"))

        store.restore(from: [SyncRecord(id: "new", data: ["k": "v"])])

        XCTAssertNil(store.get("old"))
        XCTAssertEqual(store.get("new")?.data["k"], "v")
        XCTAssertEqual(store.count, 1)
    }

    func testEncodeDecodeRoundTripPreservesRecords() throws {
        let store = LocalStore()
        store.put(SyncRecord(id: "1", data: ["title": "Draft"], status: .modified, version: 3))
        store.put(SyncRecord(id: "2", data: ["title": "Done"], status: .synced))

        let data = try store.encoded()
        let restored = LocalStore()
        try restored.decode(from: data)

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.get("1")?.data["title"], "Draft")
        XCTAssertEqual(restored.get("1")?.status, .modified)
        XCTAssertEqual(restored.get("1")?.version, 3)
        XCTAssertEqual(restored.get("2")?.status, .synced)
    }

    func testEncodingIsStableForTheSameContents() throws {
        let first = LocalStore()
        first.put(SyncRecord(id: "b", updatedAt: Date(timeIntervalSince1970: 0)))
        first.put(SyncRecord(id: "a", updatedAt: Date(timeIntervalSince1970: 0)))

        let second = LocalStore()
        second.put(SyncRecord(id: "a", updatedAt: Date(timeIntervalSince1970: 0)))
        second.put(SyncRecord(id: "b", updatedAt: Date(timeIntervalSince1970: 0)))

        // Insertion order differs; the encoded bytes must not
        XCTAssertEqual(try first.encoded(), try second.encoded())
    }

    func testMalformedDataLeavesTheStoreUntouched() {
        let store = LocalStore()
        store.put(SyncRecord(id: "keep", data: ["k": "v"]))

        XCTAssertThrowsError(try store.decode(from: Data("not json".utf8)))
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.get("keep")?.data["k"], "v")
    }

    func testSaveAndLoadRoundTripThroughAFile() throws {
        let url = makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = LocalStore()
        store.put(SyncRecord(id: "1", data: ["title": "Offline edit"], status: .modified))
        store.delete("1")
        try store.save(to: url)

        let restored = LocalStore()
        try restored.load(from: url)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.get("1")?.status, .deleted)
        XCTAssertEqual(restored.pending().count, 1)
    }

    func testLoadingAMissingFileThrows() {
        let store = LocalStore()
        XCTAssertThrowsError(try store.load(from: makeTemporaryURL()))
    }

    func testRestoredStoreResumesSyncing() throws {
        let url = makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let before = SyncEngine()
        before.localStore.put(SyncRecord(id: "1", data: ["k": "v"], status: .pending))
        try before.localStore.save(to: url)

        // A fresh process: reload the store and sync what was still pending
        let after = SyncEngine()
        try after.localStore.load(from: url)

        let result = try after.sync(
            push: { records in records.map { $0.withStatus(.synced) } },
            pull: { [] }
        )

        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(after.localStore.get("1")?.status, .synced)
    }
}
