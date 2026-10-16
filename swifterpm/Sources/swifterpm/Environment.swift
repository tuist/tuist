import Foundation

enum Environment {
    @TaskLocal
    static var values: [String: String]?

    @TaskLocal
    static var manifestValues: [String: String]?

    @TaskLocal
    static var resolutionValues: [String: String]?

    @TaskLocal
    static var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?

    /// The netrc every download authenticates against. Entry points install it once
    /// per resolution, so the unbound value means no netrc source was configured.
    @TaskLocal
    static var netrc: Netrc = .empty

    @TaskLocal
    static var keychainCredentials: KeychainCredentialCache?

    @TaskLocal
    static var warningHandler: (@Sendable (String) -> Void)? = {
        FileHandle.standardError.write(Data("Warning: \($0)\n".utf8))
    }

    static func withWarnings<T>(quiet: Bool, operation: () async throws -> T) async rethrows -> T {
        try await $warningHandler.withValue(quiet ? nil : warningHandler) { try await operation() }
    }

    static var isCI: Bool {
        ["GITHUB_RUN_ID", "CI", "BUILD_NUMBER"].contains { current[$0] != nil }
    }

    static func withNetrc<T>(
        _ netrc: Netrc,
        quiet: Bool = false,
        operation: () async throws -> T
    ) async throws -> T {
        try await withWarnings(quiet: quiet) {
            try await Environment.$netrc.withValue(netrc) {
                try await Environment.$keychainCredentials.withValue(KeychainCredentialCache()) {
                    try await operation()
                }
            }
        }
    }

    static func withManifestEnvironment<T>(
        _ environment: [String: String]?,
        resolutionEnvironment: [String: String]? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        let nativeEnvironment = resolutionEnvironment ?? (environment == nil ? resolutionValues : nil)
        return try await Environment.$resolutionValues.withValue(nativeEnvironment) {
            try await Environment.$manifestValues.withValue(environment ?? manifestValues) {
                try await operation()
            }
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
    /// Downloads retain this environment independently of filtered manifest evaluation.
    /// Native resolution can use a separate environment to retain fetch credentials.
    static var current: [String: String] {
        values ?? ProcessInfo.processInfo.environment
    }

    static var resolution: [String: String]? {
        resolutionValues ?? manifestValues
    }

    static var manifest: [String: String] {
        manifestValues ?? current
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
