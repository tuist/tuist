import Foundation
import Path

/// A digest of the manifest environment and SwiftPM mirrors used as one input to ManifestCache.
/// Values are hashed before persistence so credentials are never recorded in cleartext.
enum ManifestEnvironmentFingerprint {
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
    /// `current()`, so the environment digest remains independent of absent configuration files.
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
}
