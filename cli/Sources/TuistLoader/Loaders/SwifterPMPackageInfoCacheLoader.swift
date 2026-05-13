import FileSystem
import Foundation
import Path
import TuistConstants
import XcodeGraph

struct SwifterPMPackageInfoCacheLoader {
    private let fileSystem: FileSysteming
    private let environment: () -> [String: String]

    init(
        fileSystem: FileSysteming,
        environment: @escaping () -> [String: String]
    ) {
        self.fileSystem = fileSystem
        self.environment = environment
    }

    func load(
        scratchDirectory: AbsolutePath,
        arguments: [String]
    ) async throws -> SwifterPMPackageInfoCache? {
        guard isTruthy(environment()[Constants.EnvironmentVariables.useFastPackageResolution]) else {
            return nil
        }

        let cacheDirectory = try cacheDirectory(
            scratchDirectory: scratchDirectory,
            arguments: arguments
        )
        let indexPath = cacheDirectory.appending(component: "index.json")
        guard try await fileSystem.exists(indexPath) else {
            return nil
        }

        return try JSONDecoder().decode(
            SwifterPMPackageInfoCache.self,
            from: try await fileSystem.readFile(at: indexPath)
        )
    }

    func cachedPackageInfo(
        for dependency: SwiftPackageManagerWorkspaceState.Dependency,
        in cache: SwifterPMPackageInfoCache?
    ) async throws -> PackageInfo? {
        guard let cache else { return nil }

        let identity = dependency.packageRef.identity.lowercased()
        guard let entry = cache.packages.first(where: { $0.identity.lowercased() == identity }) else {
            return nil
        }

        return try await loadPackageInfo(at: entry.packageInfoPath)
    }

    func loadPackageInfo(at path: String) async throws -> PackageInfo {
        try JSONDecoder().decode(
            PackageInfo.self,
            from: try await fileSystem.readFile(at: try AbsolutePath(validating: path))
        )
    }

    private func cacheDirectory(
        scratchDirectory: AbsolutePath,
        arguments: [String]
    ) throws -> AbsolutePath {
        if let cachePath = argumentValue(for: "--package-info-cache-path", in: arguments) {
            return try AbsolutePath(validating: cachePath)
        }

        return scratchDirectory.appending(components: [
            "swifterpm",
            "package-info",
        ])
    }

    private func argumentValue(for argument: String, in arguments: [String]) -> String? {
        guard let argumentIndex = arguments.firstIndex(of: argument) else {
            return nil
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }
        return arguments[valueIndex]
    }

    private func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "TRUE", "yes", "YES"].contains(value)
    }
}

struct SwifterPMPackageInfoCache: Decodable {
    let root: Entry
    let packages: [Entry]

    struct Entry: Decodable {
        let identity: String
        let packageInfoPath: String
    }
}
