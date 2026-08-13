import Foundation

enum Environment {
    @TaskLocal
    static var values: [String: String]?

    @TaskLocal
    static var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?

    @TaskLocal
    static var netrc: ResolvedNetrc?

    static var isCI: Bool {
        ["GITHUB_RUN_ID", "CI", "BUILD_NUMBER"].contains { current[$0] != nil }
    }

    /// The netrc every download authenticates against. Entry points install it once
    /// per resolution, so an unset task local means no netrc source was configured.
    static var resolvedNetrc: ResolvedNetrc {
        netrc ?? .none
    }

    static func withNetrc<T>(
        _ netrc: ResolvedNetrc,
        operation: () async throws -> T
    ) async throws -> T {
        try await Environment.$netrc.withValue(netrc) {
            try await operation()
        }
    }

    static func cachedDirectoryMaterializationMode()
        -> SwifterPMCachedDirectoryMaterialization
    {
        cachedDirectoryMaterialization ?? .automatic
    }

    static func withCachedDirectoryMaterialization<T>(
        _ materialization: SwifterPMCachedDirectoryMaterialization?,
        operation: () async throws -> T
    ) async throws -> T {
        if let materialization {
            return try await Environment.$cachedDirectoryMaterialization.withValue(materialization) {
                try await operation()
            }
        }
        return try await operation()
    }

    /// The environment the process runs in. Overridable through the `values` task-local
    /// for dependency injection (notably in tests); otherwise the live process environment.
    /// Manifest evaluation observes the same environment because swifterpm inherits it into
    /// the `swift package dump-package` subprocess, so this is also the environment a cached
    /// dump was produced under.
    static var current: [String: String] {
        values ?? ProcessInfo.processInfo.environment
    }
}

extension SwifterPMCachedDirectoryMaterialization {
    init(configurationValue: String) throws {
        switch configurationValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto", "automatic":
            self = .automatic
        case "copy":
            self = .copy
        case "symlink":
            self = .symlink
        default:
            throw ToolError.message(
                "cached directory materialization must be one of: automatic, copy, symlink"
            )
        }
    }

    var shouldCopyCachedDirectories: Bool {
        switch self {
        case .automatic:
            Environment.isCI
        case .copy:
            true
        case .symlink:
            false
        }
    }
}
