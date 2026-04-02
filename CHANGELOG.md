# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-02

### Added
- `SyncEngine` coordinator with push/pull/resolve sync cycle
- `LocalStore` thread-safe in-memory record store with pending/synced/modified tracking
- `ConflictResolver` with pluggable strategies (remoteWins, localWins, latestWins, custom)
- `RetryQueue` with configurable max attempts for failed operations
- `SyncRecord` value type with status, version, and timestamp metadata
- `SyncResult` summary with pushed/pulled/conflicts/retried counts
- Zero external dependencies
