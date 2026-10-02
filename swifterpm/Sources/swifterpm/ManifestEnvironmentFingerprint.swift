import Foundation
import Path

/// A stable digest of the environment, used to key the dump-package cache.
///
/// A `Package.swift` is arbitrary Swift and can branch on environment values through
/// `PackageDescription.Context.environment`. SwiftPM forwards the entire process
/// environment to the manifest interpreter (not just a curated allowlist), so a
/// manifest's evaluated result is a function of the whole environment, not only of
/// `Package.swift`. Comparing only the modification times of `Package.swift` and the
/// cached dump therefore reuses a dump produced under a different environment, which is
/// the root cause of stale local-package manifests
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

    static func sidecarPath(forCacheFile cacheFile: AbsolutePath) -> AbsolutePath {
        cacheFile.parentDirectory.appending(component: "\(cacheFile.basename).\(sidecarExtension)")
    }

    /// The fingerprint for the environment swifterpm currently runs in.
    static func current() -> String {
        digest(for: Environment.manifest)
    }

    /// A deterministic fingerprint for `environment`, encoded as sorted JSON so a value
    /// containing the delimiter cannot collide with distinct entries: `A="x\nB=y"` must
    /// not hash the same as the two variables `A="x"`, `B="y"`.
    static func digest(for environment: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: environment, options: [.sortedKeys]
        ) else {
            return Hashing.sha256Hex(Data())
        }
        return Hashing.sha256Hex(data)
    }

    /// The fingerprint for dumping `packageDir`: the environment plus the SwiftPM mirror
    /// configuration `dump-package` reads there, since SwiftPM rewrites dependency locations and
    /// identities through the mirrors while dumping. Without any mirror configuration it equals
    /// `current()`, so dumps cached before mirrors were considered stay valid.
    static func current(packageDir: URL) async -> String {
        let environment = Environment.manifest
        var mirrorConfigurations: [String: String] = [:]
        for path in mirrorConfigurationPaths(packageDir: packageDir, environment: environment) {
            if let data = try? await fileSystem.readFile(at: path.absolutePath) {
                mirrorConfigurations[path.path] = Hashing.sha256Hex(data)
            }
        }
        guard !mirrorConfigurations.isEmpty else { return digest(for: environment) }
        mirrorConfigurations["environment"] = digest(for: environment)
        return digest(for: mirrorConfigurations)
    }

    /// The files SwiftPM loads mirrors from when `dump-package` runs in `packageDir` without
    /// `--config-path`, mirroring `MirrorConfig.load`.
    private static func mirrorConfigurationPaths(packageDir: URL, environment: [String: String]) -> [URL] {
        var paths = [
            environment["SWIFTPM_MIRROR_CONFIG"].map { URL(fileURLWithPath: $0) }
                ?? packageDir.appendingPathComponent(".swiftpm/configuration/mirrors.json"),
        ]
        if let home = environment["HOME"] {
            paths.append(URL(fileURLWithPath: home).appendingPathComponent(".swiftpm/configuration/mirrors.json"))
        }
        return paths
    }

    /// Writes the fingerprint for dumping `packageDir` next to `cacheFile`.
    static func write(forCacheFile cacheFile: AbsolutePath, packageDir: URL) async throws {
        try await fileSystem.write(
            Data(current(packageDir: packageDir).utf8),
            to: sidecarPath(forCacheFile: cacheFile)
        )
    }

    static func validate(forCacheFile cacheFile: AbsolutePath, packageDir: URL) async throws -> Validation {
        let sidecar = sidecarPath(forCacheFile: cacheFile)
        guard try await fileSystem.exists(sidecar) else { return .missing }
        let stored = try await fileSystem.readFile(at: sidecar)
        let expected = await current(packageDir: packageDir)
        return String(data: stored, encoding: .utf8) == expected ? .matching : .mismatching
    }
}
