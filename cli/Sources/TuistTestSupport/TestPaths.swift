import Foundation
import Path

public enum TestPaths {
    public static var repositoryRoot: AbsolutePath {
        do {
            return try resolveRepositoryRoot(
                environment: ProcessInfo.processInfo.environment,
                workingDirectory: AbsolutePath(validating: FileManager.default.currentDirectoryPath)
            )
        } catch {
            preconditionFailure("Could not locate the test checkout. Set TUIST_CONFIG_SRCROOT to its absolute path: \(error)")
        }
    }

    public static var fixturesDirectory: AbsolutePath {
        repositoryRoot.appending(components: "cli", "Tests", "Fixtures")
    }

    public static var examplesDirectory: AbsolutePath {
        repositoryRoot.appending(components: "examples", "xcode")
    }

    public static func snapshotDirectory(filePath: String) throws -> AbsolutePath {
        try snapshotDirectory(filePath: filePath, repositoryRoot: repositoryRoot)
    }

    static func snapshotDirectory(filePath: String, repositoryRoot: AbsolutePath) throws -> AbsolutePath {
        // Xcode maps the project directory to `/^src`; with Tuist's Xcode caching, the
        // later `/^root` mapping of the Tuist root wins for the same repository checkout.
        let prefixes = ["/^src/", "/^root/"]
        let sourcePath = try prefixes.first(where: filePath.hasPrefix).map { prefix in
            try repositoryRoot.appending(RelativePath(validating: String(filePath.dropFirst(prefix.count))))
        } ?? AbsolutePath(validating: filePath)
        return sourcePath.parentDirectory.appending(components: "__Snapshots__", sourcePath.basenameWithoutExt)
    }

    static func resolveRepositoryRoot(environment: [String: String], workingDirectory: AbsolutePath) throws -> AbsolutePath {
        if let root = environment["TUIST_CONFIG_SRCROOT"] {
            return try AbsolutePath(validating: root)
        }

        var directory = workingDirectory
        while true {
            if FileManager.default.fileExists(atPath: directory.appending(components: "cli", "Tests", "Fixtures").pathString) {
                return directory
            }
            guard directory.parentDirectory != directory else { throw ResolutionError.repositoryRootNotFound }
            directory = directory.parentDirectory
        }
    }

    enum ResolutionError: Error, Equatable {
        case repositoryRootNotFound
    }
}
