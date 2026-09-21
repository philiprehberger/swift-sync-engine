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

    func testAttemptsSurviveDequeue() {
        let queue = RetryQueue(maxAttempts: 3, baseDelay: 0)
        let record = SyncRecord(id: "1")

        queue.enqueue(record)       // attempt 1
        _ = queue.dequeueReady()    // drained for a retry, which then fails again
        queue.enqueue(record)       // attempt 2 — must not restart at 1

        XCTAssertEqual(queue.attempts(for: "1"), 2)
        XCTAssertEqual(queue.pending().first?.attempts, 2)
    }

    func testRecordIsDroppedAcrossDequeueCycles() {
        let queue = RetryQueue(maxAttempts: 3, baseDelay: 0)
        let record = SyncRecord(id: "1")

        for _ in 0..<3 {
            queue.enqueue(record)
            _ = queue.dequeueReady()
        }

        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.droppedCount, 1)
    }

    func testEnqueueReportsWhetherRecordWasQueued() {
        let queue = RetryQueue(maxAttempts: 2, baseDelay: 0)
        let record = SyncRecord(id: "1")
        XCTAssertTrue(queue.enqueue(record))
        XCTAssertFalse(queue.enqueue(record))  // exhausted maxAttempts
    }

    func testBackoffDelaysRetry() {
        let queue = RetryQueue(maxAttempts: 5, baseDelay: 10)
        queue.enqueue(SyncRecord(id: "1"))

        XCTAssertTrue(queue.dequeueReady().isEmpty)  // not due yet
        XCTAssertEqual(queue.count, 1)               // and still queued
        XCTAssertEqual(queue.dequeueReady(now: Date().addingTimeInterval(11)).count, 1)
    }

    func testBackoffDoublesWithEachAttempt() {
        let queue = RetryQueue(maxAttempts: 5, baseDelay: 10)
        let record = SyncRecord(id: "1")

        queue.enqueue(record)
        let first = queue.pending().first.map { $0.nextAttemptAt.timeIntervalSince($0.enqueuedAt) }
        _ = queue.dequeueAll()

        queue.enqueue(record)
        let second = queue.pending().first.map { $0.nextAttemptAt.timeIntervalSince($0.enqueuedAt) }

        XCTAssertEqual(first ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(second ?? 0, 20, accuracy: 0.001)
    }

    func testBackoffIsCappedAtMaxDelay() {
        let queue = RetryQueue(maxAttempts: 20, baseDelay: 10, maxDelay: 25)
        let record = SyncRecord(id: "1")

        for _ in 0..<5 {
            queue.enqueue(record)
            _ = queue.dequeueAll()
        }
        queue.enqueue(record)

        let delay = queue.pending().first.map { $0.nextAttemptAt.timeIntervalSince($0.enqueuedAt) }
        XCTAssertEqual(delay ?? 0, 25, accuracy: 0.001)
    }

    func testMarkSucceededClearsQueuedItemAndHistory() {
        let queue = RetryQueue(maxAttempts: 3, baseDelay: 0)
        let record = SyncRecord(id: "1")
        queue.enqueue(record)
        queue.enqueue(record)

        queue.markSucceeded("1")

        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.attempts(for: "1"), 0)
        XCTAssertTrue(queue.enqueue(record))  // history cleared, back to attempt 1
    }

    func testDequeueAllIgnoresBackoff() {
        let queue = RetryQueue(maxAttempts: 3, baseDelay: 60)
        queue.enqueue(SyncRecord(id: "1"))
        XCTAssertEqual(queue.dequeueAll().count, 1)
    }

    func testClearResetsAttemptHistory() {
        let queue = RetryQueue(maxAttempts: 2, baseDelay: 0)
        let record = SyncRecord(id: "1")
        queue.enqueue(record)
        queue.clear()
        XCTAssertEqual(queue.attempts(for: "1"), 0)
        XCTAssertEqual(queue.droppedCount, 0)
    }
}
