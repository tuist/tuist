import Foundation
import TuistEnvironment

/// Divides the byte budget a Tuist runner stages for the cache volume it mounted between the
/// tenants that write into it.
///
/// One staged budget rather than one per tenant: the host sizes the volume and knows nothing about
/// how the CLI lays a cache out, so what it can say is how many bytes the CLI may occupy. Splitting
/// it here keeps that boundary narrow, and keeps the split somewhere both pruners read rather than
/// somewhere each of them is told.
///
/// The module cache takes almost all of it. It holds the artifacts a build actually links, it is
/// the reason the volume exists, and a miss costs a download; the support caches hold what the CLI
/// derives along the way, where a miss costs a recompute. They are also small in absolute terms —
/// a compiled helpers module is the same size whatever the volume is — so their share is capped
/// rather than proportional, and the percentage only keeps a small budget from handing them a
/// slice the module cache cannot spare.
public enum CacheBudget {
    /// Unset outside a runner, where the cache is the user's own directory and unbounded.
    static var total: Int? {
        Environment.current.variables["TUIST_CACHE_MAX_BYTES"].flatMap { Int($0) }
    }

    private static let supportCeiling = 1024 * 1024 * 1024
    private static let supportPercent = 10

    /// What the caches derived along the way may occupy, enforced by `SupportCachePruner`.
    public static var supportCaches: Int? {
        total.map { min(supportCeiling, $0 * supportPercent / 100) }
    }

    /// What the module cache may occupy — the rest, and so the whole budget wherever it is unset.
    public static var moduleCache: Int? {
        guard let total, let supportCaches else { return nil }
        return total - supportCaches
    }
}
