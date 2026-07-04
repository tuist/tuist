import Foundation

/// Prefetches CAS artifacts referenced by a cache value ahead of the compiler
/// requesting them.
///
/// The compiler consumes the daemon nearly serially per compilation task:
/// key query, then one load per referenced output, then replay. Each load is
/// individually cheap, but tens of thousands of them dominate a fully-warm
/// build. The key-value payload the daemon returns already names every
/// artifact the compiler is about to ask for, so the daemon can download them
/// concurrently while the compiler is still processing the query response,
/// turning the subsequent loads into memory hits.
///
/// Entries are consumed at most once; a second load for the same ID falls
/// back to a direct fetch. Failed prefetches are discarded so the fallback
/// path retries them. The staged-bytes budget bounds memory: once exceeded,
/// new stage requests are skipped until consumption frees space.
public actor CASPrefetcher {
    public typealias Fetch = @Sendable (String) async throws -> Data

    private let fetch: Fetch
    private let maxStagedBytes: Int
    private let maxEntries: Int

    private var inflight: [String: Task<Data, Error>] = [:]
    private var stagedBytes = 0

    public init(
        maxStagedBytes: Int = 512 * 1024 * 1024,
        maxEntries: Int = 4096,
        fetch: @escaping Fetch
    ) {
        self.maxStagedBytes = maxStagedBytes
        self.maxEntries = maxEntries
        self.fetch = fetch
    }

    /// Starts a background download for the artifact unless one is already
    /// staged or the budget is exhausted.
    public func stage(casID: String) {
        let key = casID.uppercased()
        guard inflight[key] == nil, inflight.count < maxEntries, stagedBytes < maxStagedBytes else { return }
        let fetch = fetch
        let task = Task<Data, Error> {
            try await fetch(key)
        }
        inflight[key] = task
        Task {
            if let data = try? await task.value {
                self.recordStaged(bytes: data.count, for: key)
            } else {
                self.discard(key)
            }
        }
    }

    /// Returns the prefetched artifact and releases it, or nil when the
    /// artifact was never staged or its download failed.
    public func take(casID: String) async -> Data? {
        let key = casID.uppercased()
        guard let task = inflight.removeValue(forKey: key) else { return nil }
        guard let data = try? await task.value else { return nil }
        stagedBytes -= data.count
        if stagedBytes < 0 { stagedBytes = 0 }
        return data
    }

    private func recordStaged(bytes: Int, for key: String) {
        guard inflight[key] != nil else { return }
        stagedBytes += bytes
    }

    private func discard(_ key: String) {
        inflight.removeValue(forKey: key)
    }
}
