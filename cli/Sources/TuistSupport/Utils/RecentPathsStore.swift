import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment

public struct RecentPathMetadata: Hashable, Equatable, Codable {
    let lastUpdated: Date
    public init(lastUpdated: Date) {
        self.lastUpdated = lastUpdated
    }
}

/// This is a utility to record the paths the user interacts with.
/// This is recorded either from the working directory or the --path argument when invoking a command.
/// The information can then be used by tools like MCP servers to allow users to interact with their most recent
/// projects.
@Mockable
public protocol RecentPathsStoring {
    /// Records that the user has interacted with a given path.
    /// - Parameters:
    ///   - path: The path the user has interacted with.
    ///   - date: The date of interaction
    func remember(path: AbsolutePath, date: Date) async throws

    /// Returns the list of paths the user has interacted with along with the last date of interaction.
    /// - Returns: A dictionary where the keys are the paths, and the values are the last time the user interacted with those
    /// paths.
    func read() async throws -> [AbsolutePath: RecentPathMetadata]
}

public struct RecentPathsStore: RecentPathsStoring {
    @TaskLocal public static var current: RecentPathsStoring = RecentPathsStore(
        storageDirectory: Environment.current
            .stateDirectory
    )

    private let fileSystem: FileSystem
    private let storageDirectory: AbsolutePath

    public init(storageDirectory: AbsolutePath) {
        self.init(fileSystem: FileSystem(), storageDirectory: storageDirectory)
    }

    init(fileSystem: FileSystem, storageDirectory: AbsolutePath) {
        self.fileSystem = fileSystem
        self.storageDirectory = storageDirectory
    }

    public func remember(path: AbsolutePath, date: Date) async throws {
        try POSIXDirectory.ensureExists(storageDirectory)
        let lock = FileLock(at: storageDirectory.appending(component: "recent-paths.json.lock"))
        try await lock.withExclusiveLock {
            var content = try await readUnlocked()
            content[path] = RecentPathMetadata(lastUpdated: date)
            try writeUnlocked(content)
        }
    }

    public func read() async throws -> [AbsolutePath: RecentPathMetadata] {
        let lock = FileLock(at: storageDirectory.appending(component: "recent-paths.json.lock"))
        return try await lock.withExclusiveLock {
            try await readUnlocked()
        }
    }

    private func readUnlocked() async throws -> [AbsolutePath: RecentPathMetadata] {
        let recentPathsFile = recentPathsFile(storageDirectory: storageDirectory)
        guard try await fileSystem.exists(recentPathsFile) else { return [:] }
        return try await fileSystem.readJSONFile(at: recentPathsFile)
    }

    private func writeUnlocked(_ content: [AbsolutePath: RecentPathMetadata]) throws {
        let recentPathsFile = recentPathsFile(storageDirectory: storageDirectory)
        let data = try JSONEncoder().encode(content)
        // Use Foundation's atomic write which uses plain rename(2) — safe under
        // the exclusive flock and unaffected by `renamex_np`'s `RENAME_EXCL`
        // semantics that surface as "File exists" errors under concurrent writes.
        try data.write(to: URL(fileURLWithPath: recentPathsFile.pathString), options: [.atomic])
    }

    private func recentPathsFile(storageDirectory: AbsolutePath) -> AbsolutePath {
        storageDirectory.appending(component: "recent-paths.json")
    }
}

extension RecentPathsStoring {
    public func remember(path: AbsolutePath) async throws {
        try await remember(path: path, date: Date())
    }
}
