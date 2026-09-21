# SyncEngine

[![Tests](https://github.com/philiprehberger/swift-sync-engine/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/swift-sync-engine/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fphiliprehberger%2Fswift-sync-engine%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/philiprehberger/swift-sync-engine)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fphiliprehberger%2Fswift-sync-engine%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/philiprehberger/swift-sync-engine)

![SyncEngine](https://raw.githubusercontent.com/philiprehberger/swift-sync-engine/main/package-card.webp)

Offline-first data sync engine with conflict resolution, retry queues, and local caching

## Requirements

- Swift >= 6.0
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/philiprehberger/swift-sync-engine.git", from: "0.4.0")
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

### Async Backends

Real backends are `async`, so `sync` has an `async` overload that awaits them instead of blocking:

```swift
let result = try await engine.sync(
    push: { records in try await api.upload(records) },
    pull: { try await api.fetchChanges() }
)
```

Same cycle as the synchronous form — pending records first, then due retries, then the pull — and the same `SyncResult`.

### Local Store

Store and query records offline:

```swift
let store = engine.localStore
store.put(SyncRecord(id: "1", data: ["title": "Draft"]))
store.markModified("1")  // flag as changed locally

let pending = store.pending()  // records needing sync
let all = store.all()
```

### Deleting Records

Soft-delete a record so the deletion syncs to your backend:

```swift
engine.localStore.delete("1")  // marks .deleted; included in pending()

// On the next sync, a confirmed push clears the tombstone locally.
// A remote record arriving with .deleted status removes the local copy.
let result = try engine.sync(push: myAPI.upload, pull: myAPI.fetch)
```

Use `remove(_:)` for an immediate local-only removal that does not sync.

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

Failed push operations are queued for retry with exponential backoff:

```swift
// Up to 5 attempts; 2s before the first retry, doubling each time, capped at 60s
let engine = SyncEngine(queue: RetryQueue(maxAttempts: 5, baseDelay: 2, maxDelay: 60))

// After a failed sync, items are in the retry queue
print(engine.retryQueue.count)
print(engine.retryQueue.attempts(for: "doc-1"))  // attempts so far, across cycles

// Each sync picks up whatever is due
let result = try engine.sync(push: myAPI.upload, pull: myAPI.fetch)
print("Retried: \(result.retried), failed: \(result.failed), dropped: \(result.dropped)")
```

Attempt counts are tracked per record id and survive dequeuing, so a record that keeps failing is dropped once it reaches `maxAttempts` instead of retrying forever. A record that is both pending locally and queued for retry is pushed once per cycle, not twice.

### Persistence

The local store is in memory, so save it to keep offline edits across launches:

```swift
let url = URL.documentsDirectory.appending(path: "sync-store.json")

// On the way out
try engine.localStore.save(to: url)

// On the way back in — pending records resume syncing
try engine.localStore.load(from: url)
let result = try engine.sync(push: myAPI.upload, pull: myAPI.fetch)
```

Use `encoded()` / `decode(from:)` for the raw JSON, or `snapshot()` / `restore(from:)` to move records through your own storage.

### One Sync at a Time

```swift
do {
    let result = try engine.sync(push: myAPI.upload, pull: myAPI.fetch)
} catch SyncError.syncInProgress {
    // Another sync is running — overlapping cycles would interleave their pushes
}
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
let stats = engine.localStore.statistics  // (total, pending, synced, modified, conflicted, deleted)
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
| `.sync(push:pull:onProgress:)` (async) | Sync with `async` push/pull closures |
| `.lastSyncResult` | Most recent sync result |

### `LocalStore`

| Method | Description |
|--------|-------------|
| `.put(_:)` | Store or update a record |
| `.get(_:)` | Retrieve by ID |
| `.remove(_:)` | Remove by ID (local only, does not sync) |
| `.delete(_:)` | Soft-delete a record so the deletion syncs to remote |
| `.all()` | Get all records |
| `.pending()` | Get pending/modified records |
| `.markSynced(_:)` | Mark as synced |
| `.markModified(_:)` | Mark as locally modified |
| `.clear()` | Remove all records |
| `.query(where:)` | Filter records by predicate |
| `.putAll(_:)` | Bulk insert records |
| `.statistics` | Count by status (total, pending, synced, modified, conflicted, deleted) |
| `.snapshot()` | Every record as a plain array |
| `.restore(from:)` | Replace contents with a snapshot |
| `.encoded()` | Encode the store as JSON with stable ordering |
| `.decode(from:)` | Replace contents from JSON |
| `.save(to:)` | Write the store to a file atomically |
| `.load(from:)` | Read the store back from a file |

### `ConflictResolver`

| Method | Description |
|--------|-------------|
| `.resolve(local:remote:)` | Resolve a conflict between two records |
| `.strategy` | Get/set the resolution strategy |
| `.resolvedCount` | Number of conflicts resolved |

### `RetryQueue`

| Method | Description |
|--------|-------------|
| `RetryQueue(maxAttempts:baseDelay:maxDelay:)` | Create a queue with attempt limit and backoff bounds |
| `.enqueue(_:)` | Record a failed attempt; returns `false` if the record was dropped |
| `.dequeueReady(now:)` | Remove and return the records whose backoff has elapsed |
| `.dequeueAll()` | Remove and return all queued records, regardless of backoff |
| `.markSucceeded(_:)` | Forget a record that has since synced, including its attempt history |
| `.attempts(for:)` | Failed attempts for a record id, across cycles |
| `.pending()` | Peek at queued items |
| `.count` | Number of queued items |
| `.droppedCount` | Records abandoned for exhausting `maxAttempts` |
| `.clear()` | Clear the queue, attempt history, and dropped counter |

### `SyncResult`

| Property | Description |
|----------|-------------|
| `.pushed` | Records pushed to remote |
| `.pulled` | Records pulled from remote |
| `.conflicts` | Conflicts resolved |
| `.retried` | Retry-queue records pushed |
| `.failed` | Records whose push failed and were queued for retry |
| `.dropped` | Records abandoned after exhausting `maxAttempts` |
| `.total` | Total records processed |

### `SyncError`

| Case | Description |
|------|-------------|
| `.syncInProgress` | A sync was started while another was still running |

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
