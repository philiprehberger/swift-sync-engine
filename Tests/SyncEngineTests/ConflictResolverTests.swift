import XCTest
@testable import SyncEngine

final class ConflictResolverTests: XCTestCase {
    func testRemoteWins() {
        let resolver = ConflictResolver(strategy: .remoteWins)
        let local = SyncRecord(id: "1", data: ["v": "local"])
        let remote = SyncRecord(id: "1", data: ["v": "remote"])
        let result = resolver.resolve(local: local, remote: remote)
        XCTAssertEqual(result.data["v"], "remote")
        XCTAssertEqual(result.status, .synced)
    }

    func testLocalWins() {
        let resolver = ConflictResolver(strategy: .localWins)
        let local = SyncRecord(id: "1", data: ["v": "local"])
        let remote = SyncRecord(id: "1", data: ["v": "remote"])
        let result = resolver.resolve(local: local, remote: remote)
        XCTAssertEqual(result.data["v"], "local")
    }

    func testLatestWins() {
        let resolver = ConflictResolver(strategy: .latestWins)
        let old = SyncRecord(id: "1", data: ["v": "old"], updatedAt: Date(timeIntervalSince1970: 1000))
        let newer = SyncRecord(id: "1", data: ["v": "new"], updatedAt: Date(timeIntervalSince1970: 2000))
        let result = resolver.resolve(local: old, remote: newer)
        XCTAssertEqual(result.data["v"], "new")
    }

    func testCustomStrategy() {
        let resolver = ConflictResolver(strategy: .custom { local, remote in
            var merged = local
            merged.data.merge(remote.data) { _, new in new }
            return merged
        })
        let local = SyncRecord(id: "1", data: ["a": "1"])
        let remote = SyncRecord(id: "1", data: ["b": "2"])
        let result = resolver.resolve(local: local, remote: remote)
        XCTAssertEqual(result.data["a"], "1")
        XCTAssertEqual(result.data["b"], "2")
    }

    func testResolvedCount() {
        let resolver = ConflictResolver(strategy: .remoteWins)
        let a = SyncRecord(id: "1")
        let b = SyncRecord(id: "1")
        _ = resolver.resolve(local: a, remote: b)
        _ = resolver.resolve(local: a, remote: b)
        XCTAssertEqual(resolver.resolvedCount, 2)
    }

    func testResetStats() {
        let resolver = ConflictResolver(strategy: .remoteWins)
        _ = resolver.resolve(local: SyncRecord(id: "1"), remote: SyncRecord(id: "1"))
        resolver.resetStats()
        XCTAssertEqual(resolver.resolvedCount, 0)
    }
}
