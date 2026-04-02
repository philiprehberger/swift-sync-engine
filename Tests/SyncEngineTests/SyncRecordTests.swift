import XCTest
@testable import SyncEngine

final class SyncRecordTests: XCTestCase {
    func testCreateRecord() {
        let record = SyncRecord(id: "1", data: ["key": "value"])
        XCTAssertEqual(record.id, "1")
        XCTAssertEqual(record.data["key"], "value")
        XCTAssertEqual(record.status, .pending)
        XCTAssertEqual(record.version, 1)
    }

    func testWithStatus() {
        let record = SyncRecord(id: "1")
        let synced = record.withStatus(.synced)
        XCTAssertEqual(synced.status, .synced)
        XCTAssertEqual(synced.id, "1")
    }

    func testIncrementVersion() {
        let record = SyncRecord(id: "1", version: 1)
        let v2 = record.incrementVersion()
        XCTAssertEqual(v2.version, 2)
    }
}
