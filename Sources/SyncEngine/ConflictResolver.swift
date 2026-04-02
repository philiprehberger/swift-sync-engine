import Foundation

/// Strategy for resolving conflicts between local and remote records.
public enum ConflictStrategy: Sendable {
    /// Remote wins — always use the remote version.
    case remoteWins
    /// Local wins — always use the local version.
    case localWins
    /// Latest wins — use whichever has the most recent updatedAt.
    case latestWins
    /// Custom merge function.
    case custom(@Sendable (SyncRecord, SyncRecord) -> SyncRecord)
}

/// Resolves conflicts between local and remote records.
public final class ConflictResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var _strategy: ConflictStrategy
    private var _resolvedCount: Int = 0

    /// Create a resolver with the given strategy.
    public init(strategy: ConflictStrategy = .latestWins) {
        self._strategy = strategy
    }

    /// The current conflict resolution strategy.
    public var strategy: ConflictStrategy {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _strategy
        }
        set {
            lock.lock()
            _strategy = newValue
            lock.unlock()
        }
    }

    /// Number of conflicts resolved.
    public var resolvedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _resolvedCount
    }

    /// Resolve a conflict between a local and remote record.
    public func resolve(local: SyncRecord, remote: SyncRecord) -> SyncRecord {
        lock.lock()
        let strat = _strategy
        _resolvedCount += 1
        lock.unlock()

        var result: SyncRecord
        switch strat {
        case .remoteWins:
            result = remote
        case .localWins:
            result = local
        case .latestWins:
            result = local.updatedAt >= remote.updatedAt ? local : remote
        case .custom(let merge):
            result = merge(local, remote)
        }
        return result.withStatus(.synced)
    }

    /// Reset the resolved count.
    public func resetStats() {
        lock.lock()
        _resolvedCount = 0
        lock.unlock()
    }
}
