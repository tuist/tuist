import Foundation

/// The dependency mirrors configured with `swift package config set-mirror`, loaded the way
/// SwiftPM loads them: the package's own configuration applies as a whole when it has any
/// entry, otherwise the shared one does, and a location is mirrored only on an exact match.
struct MirrorConfig: Sendable {
    private var mirrors: [String: String] = [:]

    static func load(packageDir: URL, configPath: URL?) async throws -> MirrorConfig {
        let environment = Environment.current
        let localPath: URL
        if let customPath = environment["SWIFTPM_MIRROR_CONFIG"] {
            guard customPath.hasPrefix("/") else {
                throw ToolError.message("SWIFTPM_MIRROR_CONFIG must be an absolute path: \(customPath)")
            }
            localPath = URL(fileURLWithPath: customPath)
        } else {
            localPath = packageDir.appendingPathComponent(".swiftpm/configuration/mirrors.json")
        }
        let local = try await mirrors(at: localPath)
        if !local.isEmpty {
            return MirrorConfig(mirrors: local)
        }
        guard let sharedPath = try await sharedMirrorsPath(configPath: configPath, environment: environment)
        else {
            return MirrorConfig()
        }
        return MirrorConfig(mirrors: try await mirrors(at: sharedPath))
    }

    func effectiveLocation(for location: String) -> String {
        mirrors[location] ?? location
    }

    private static func mirrors(at path: URL) async throws -> [String: String] {
        guard try await fileSystem.exists(path.absolutePath) else { return [:] }
        let data = try await fileSystem.readFile(at: path.absolutePath)
        let storage: Storage
        do {
            storage = try JSONDecoder().decode(Storage.self, from: data)
        } catch {
            throw ToolError.message("invalid mirrors configuration at \(path.path): \(error)")
        }
        return Dictionary(
            storage.object.map { ($0.original, $0.mirror) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// `--config-path` names SwiftPM's shared configuration directory. SwifterPM also accepts a
    /// path to `registries.json` there, in which case mirrors live next to it.
    private static func sharedMirrorsPath(
        configPath: URL?,
        environment: [String: String]
    ) async throws -> URL? {
        if let configPath {
            if try await fileSystem.exists(configPath.absolutePath, isDirectory: false) {
                return configPath.deletingLastPathComponent().appendingPathComponent("mirrors.json")
            }
            return configPath.appendingPathComponent("mirrors.json")
        }
        return environment["HOME"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(".swiftpm/configuration/mirrors.json")
        }
    }

    private struct Storage: Decodable {
        struct Mirror: Decodable {
            let original: String
            let mirror: String
        }

        let object: [Mirror]
    }
}
