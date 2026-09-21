import Foundation

/// Errors thrown by the sync engine.
public enum SyncError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A sync was started while another sync was still running.
    ///
    /// Overlapping syncs interleave their pushes and produce counts that belong to neither
    /// cycle, so the second caller is refused rather than allowed to corrupt both results.
    case syncInProgress

    public var description: String {
        switch self {
        case .syncInProgress:
            return "A sync is already in progress"
        }
    }
}
