import Foundation

/// A stable digest of the process environment, used to key the dump-package cache.
///
/// A `Package.swift` is arbitrary Swift and can branch on environment values through
/// `PackageDescription.Context.environment`. SwiftPM forwards the entire process
/// environment to the manifest interpreter (not just a curated allowlist), so a
/// manifest's evaluated result is a function of the whole environment — not only of
/// `Package.swift`. Comparing only the modification times of `Package.swift` and the
/// cached dump therefore reuses a dump that was produced under a different environment,
/// which is the root cause of stale local-package manifests
/// (see https://github.com/tuist/tuist/issues/12130).
///
/// The fingerprint is stored as a sidecar (`.envhash`) next to each cached dump and
/// compared on read. It is a one-way digest, so secret-bearing variables never reach
/// disk in cleartext.
enum ManifestEnvironmentFingerprint {
    enum Validation: Sendable {
        /// A stored fingerprint exists and matches the current environment.
        case matching
        /// A stored fingerprint exists but differs from the current environment.
        case mismatching
        /// No sidecar exists (for example a cache written before this check existed).
        case missing
    }

    static let sidecarExtension = "envhash"

    static func sidecarPath(forCacheFile cacheFile: URL) -> URL {
        cacheFile.appendingPathExtension(sidecarExtension)
    }

    /// The fingerprint for the current process environment.
    static func current() -> String {
        digest(for: ProcessInfo.processInfo.environment)
    }

    /// A deterministic fingerprint for `environment`. Key-value pairs are sorted so the
    /// digest is independent of dictionary iteration order.
    static func digest(for environment: [String: String]) -> String {
        Hashing.stable(
            environment
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "\n")
        )
    }

    /// Writes the current environment fingerprint next to `cacheFile`.
    static func write(forCacheFile cacheFile: URL) async throws {
        try await fileSystem.atomicWrite(
            Data(current().utf8),
            to: sidecarPath(forCacheFile: cacheFile)
        )
    }

    static func validate(forCacheFile cacheFile: URL) async throws -> Validation {
        let sidecar = sidecarPath(forCacheFile: cacheFile)
        guard try await fileSystem.exists(sidecar.absolutePath) else { return .missing }
        let stored = try await fileSystem.readFile(at: sidecar.absolutePath)
        return String(data: stored, encoding: .utf8) == current() ? .matching : .mismatching
    }
}
