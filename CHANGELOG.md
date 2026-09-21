# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-09-21

### Added
- `async` overload of `sync(push:pull:onProgress:)` taking `async` push and pull closures, so network-backed backends no longer have to block the calling thread
- `SyncError.syncInProgress`, thrown when a sync starts while another is still running — `isSyncing` was tracked but never enforced, and overlapping cycles interleaved their pushes
- `SyncResult.failed` (records whose push failed and were queued) and `.dropped` (records abandoned after exhausting `maxAttempts`); both default so the existing initializer stays source-compatible
- Exponential backoff in `RetryQueue`: `RetryQueue(maxAttempts:baseDelay:maxDelay:)`, `RetryItem.nextAttemptAt`, `RetryItem.isReady(at:)`, and `dequeueReady(now:)`
- `RetryQueue.markSucceeded(_:)`, `.attempts(for:)`, and `.droppedCount`
- `LocalStore` persistence: `snapshot()`, `restore(from:)`, `encoded(using:)`, `decode(from:using:)`, `save(to:using:)`, and `load(from:using:)`, so offline edits survive a relaunch

### Fixed
- `RetryQueue.maxAttempts` was never enforced: `dequeueAll()` discarded attempt counts, so a re-enqueued record always restarted at attempt 1 and was retried forever. Attempts are now tracked per record id and survive dequeuing
- A record that failed to push stayed `.pending` in the store *and* sat in the retry queue, so every later cycle pushed it twice. The retry batch is now de-duplicated against the pending batch
- A record confirmed by a push was left in the retry queue, which re-pushed an already-synced record on the next cycle. Confirmed records are now cleared from the queue
- `sync(push:pull:)` pushed pending records, queued them on failure, then immediately dequeued and pushed the same records again inside the same cycle

### Changed
- Records queued for retry now wait out their backoff (default: 1s before the first retry, doubling to a 300s cap) instead of being retried in the same cycle. Failed records also remain `.pending` in the store, so the next cycle pushes them regardless
- `RetryQueue.enqueue(_:)` returns a discardable `Bool` reporting whether the record was queued or dropped
- `RetryQueue.clear()` also clears the attempt history and dropped counter
- `sync(push:pull:)` now delegates to `sync(push:pull:onProgress:)` — one implementation instead of two divergent copies

## [0.3.0] - 2026-07-15

### Added
- `LocalStore.delete(_:)` for soft-deleting records so deletions sync to remote (returns whether the id existed)
- End-to-end deletion (tombstone) sync: `pending()` now includes `.deleted` records; a confirmed push clears the tombstone locally, and a pulled remote `.deleted` record removes the local copy
- `LocalStore.statistics` now reports `conflicted` and `deleted` counts

### Changed
- `LocalStore.statistics` tuple extended to `(total, pending, synced, modified, conflicted, deleted)`
- `Package.swift` now declares the standard `platforms:` array (macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+) and explicit target paths

## [0.2.0] - 2026-04-02

### Added
- `sync(push:pull:onProgress:)` with progress reporting callback
- `SyncEngine.lastSyncResult` for accessing the most recent sync result
- `LocalStore.query(where:)` for predicate-based record filtering
- `LocalStore.putAll(_:)` for bulk record insertion
- `LocalStore.statistics` for record count breakdown by status

### Fixed
- Update swift-tools-version from 5.9 to 6.0

## [0.1.0] - 2026-04-02

### Added
- `SyncEngine` coordinator with push/pull/resolve sync cycle
- `LocalStore` thread-safe in-memory record store with pending/synced/modified tracking
- `ConflictResolver` with pluggable strategies (remoteWins, localWins, latestWins, custom)
- `RetryQueue` with configurable max attempts for failed operations
- `SyncRecord` value type with status, version, and timestamp metadata
- `SyncResult` summary with pushed/pulled/conflicts/retried counts
- Zero external dependencies
