# SyncEngine

[![Tests](https://github.com/philiprehberger/swift-sync-engine/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/swift-sync-engine/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fphiliprehberger%2Fswift-sync-engine%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/philiprehberger/swift-sync-engine)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fphiliprehberger%2Fswift-sync-engine%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/philiprehberger/swift-sync-engine)

Offline-first data sync engine with conflict resolution, retry queues, and local caching

## Requirements

- Swift >= 6.0
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/philiprehberger/swift-sync-engine.git", from: "0.2.0")
]
```

Then add `"SyncEngine"` to your target dependencies:

```swift
.target(name: "YourTarget", dependencies: [
    .product(name: "SyncEngine", package: "swift-sync-engine")
])
```

## Usage

```swift
import SyncEngine

let engine = SyncEngine()

// Store data locally
engine.localStore.put(SyncRecord(id: "user-1", data: ["name": "Alice"]))

// Sync with your backend
let result = try engine.sync(
    push: { records in myAPI.upload(records) },
    pull: { myAPI.fetchChanges() }
)

print("Pushed: \(result.pushed), Pulled: \(result.pulled), Conflicts: \(result.conflicts)")
```

### Local Store

Store and query records offline:

```swift
let store = engine.localStore
store.put(SyncRecord(id: "1", data: ["title": "Draft"]))
store.markModified("1")  // flag as changed locally

let pending = store.pending()  // records needing sync
let all = store.all()
```

### Conflict Resolution

Choose how to handle conflicts when local and remote diverge:

```swift
// Remote always wins
let engine = SyncEngine(resolver: ConflictResolver(strategy: .remoteWins))

// Local always wins
let engine = SyncEngine(resolver: ConflictResolver(strategy: .localWins))

// Most recent wins (default)
let engine = SyncEngine(resolver: ConflictResolver(strategy: .latestWins))

// Custom merge
let engine = SyncEngine(resolver: ConflictResolver(strategy: .custom { local, remote in
    var merged = local
    merged.data.merge(remote.data) { _, new in new }
    return merged
}))
```

### Retry Queue

Failed push operations are automatically queued for retry:

```swift
let engine = SyncEngine(queue: RetryQueue(maxAttempts: 5))

// After a failed sync, items are in the retry queue
print(engine.retryQueue.count)

// They'll be retried on the next sync cycle
let result = try engine.sync(push: myAPI.upload, pull: myAPI.fetch)
print("Retried: \(result.retried)")
```

### Progress Reporting

```swift
let result = try engine.sync(
    push: { records in api.upload(records) },
    pull: { api.fetchChanges() },
    onProgress: { current, total in
        print("Progress: \(current)/\(total)")
    }
)
```

### Query and Bulk Operations

```swift
let users = engine.localStore.query { $0.data["type"] == "user" }
engine.localStore.putAll(records)
let stats = engine.localStore.statistics  // (total: 10, pending: 2, synced: 7, modified: 1)
```

### Sync Records

```swift
var record = SyncRecord(id: "doc-1", data: ["content": "Hello"], version: 1)
record = record.incrementVersion()  // version 2, updated timestamp
record = record.withStatus(.synced)
```

## API

### `SyncEngine`

| Method | Description |
|--------|-------------|
| `SyncEngine(store:queue:resolver:)` | Create with optional custom components |
| `.sync(push:pull:)` | Perform a full sync cycle |
| `.localStore` | Access the local store |
| `.retryQueue` | Access the retry queue |
| `.conflictResolver` | Access the conflict resolver |
| `.isSyncing` | Whether a sync is in progress |
| `.sync(push:pull:onProgress:)` | Sync with progress callback |
| `.lastSyncResult` | Most recent sync result |

### `LocalStore`

| Method | Description |
|--------|-------------|
| `.put(_:)` | Store or update a record |
| `.get(_:)` | Retrieve by ID |
| `.remove(_:)` | Remove by ID |
| `.all()` | Get all records |
| `.pending()` | Get pending/modified records |
| `.markSynced(_:)` | Mark as synced |
| `.markModified(_:)` | Mark as locally modified |
| `.clear()` | Remove all records |
| `.query(where:)` | Filter records by predicate |
| `.putAll(_:)` | Bulk insert records |
| `.statistics` | Count by status (total, pending, synced, modified) |

### `ConflictResolver`

| Method | Description |
|--------|-------------|
| `.resolve(local:remote:)` | Resolve a conflict between two records |
| `.strategy` | Get/set the resolution strategy |
| `.resolvedCount` | Number of conflicts resolved |

### `RetryQueue`

| Method | Description |
|--------|-------------|
| `.enqueue(_:)` | Add a failed record to retry |
| `.dequeueAll()` | Remove and return all queued records |
| `.pending()` | Peek at queued items |
| `.count` | Number of queued items |

## Development

```bash
swift build
swift test
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/swift-sync-engine)

🐛 [Report issues](https://github.com/philiprehberger/swift-sync-engine/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/swift-sync-engine/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
