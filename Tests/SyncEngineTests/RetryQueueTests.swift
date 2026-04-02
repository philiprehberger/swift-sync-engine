import XCTest
@testable import SyncEngine

final class RetryQueueTests: XCTestCase {
    func testEnqueueAndDequeue() {
        let queue = RetryQueue()
        queue.enqueue(SyncRecord(id: "1"))
        let items = queue.dequeueAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "1")
        XCTAssertEqual(queue.count, 0)
    }

    func testMaxAttempts() {
        let queue = RetryQueue(maxAttempts: 2)
        let record = SyncRecord(id: "1")
        queue.enqueue(record) // attempt 1
        queue.enqueue(record) // attempt 2 -> dropped
        XCTAssertEqual(queue.count, 0)
    }

    func testPending() {
        let queue = RetryQueue()
        queue.enqueue(SyncRecord(id: "1"))
        queue.enqueue(SyncRecord(id: "2"))
        XCTAssertEqual(queue.pending().count, 2)
    }

    func testClear() {
        let queue = RetryQueue()
        queue.enqueue(SyncRecord(id: "1"))
        queue.clear()
        XCTAssertEqual(queue.count, 0)
    }

    func testIncrementAttempts() {
        let queue = RetryQueue(maxAttempts: 5)
        let record = SyncRecord(id: "1")
        queue.enqueue(record)
        queue.enqueue(record) // same id -> increments
        let items = queue.pending()
        XCTAssertEqual(items.first?.attempts, 2)
    }
}
