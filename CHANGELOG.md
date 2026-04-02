# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
