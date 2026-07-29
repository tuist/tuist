import Foundation

enum Environment {
    @TaskLocal
    static var values: [String: String]?

    @TaskLocal
    static var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?

    static var isCI: Bool {
        ["GITHUB_RUN_ID", "CI", "BUILD_NUMBER"].contains { environment[$0] != nil }
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

    private static var environment: [String: String] {
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
