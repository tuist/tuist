import FileSystem
import Foundation
import Mockable
import Path
import ServiceContextModule

private enum RecentPathsContextKey: ServiceContextKey {
    typealias Value = RecentPathsRecording
}

extension ServiceContext {
    public var recentPaths: RecentPathsRecording? {
        get {
            self[RecentPathsContextKey.self]
        } set {
            self[RecentPathsContextKey.self] = newValue
        }
    }
}

/// This is a utility to record the paths the user interacts with.
/// This is recorded either from the working directory or the --path argument when invoking a command.
/// The information can then be used by tools like MCP servers to allow users to interact with their most recent
/// projects.
public protocol RecentPathsRecording {
    /// Records that the user has interacted with a given path.
    /// - Parameters:
    ///   - path: The path the user has interacted with.
    func record(path: AbsolutePath) async throws

    /// Returns the list of paths the user has interacted with along with the last date of interaction.
    /// - Returns: A dictionary where the keys are the paths, and the values are the last time the user interacted with those
    /// paths.
    func read() async throws -> [AbsolutePath: Date]
}

public struct RecentPathsRecorder: RecentPathsRecording {
    private let fileSystem: FileSystem
    private let storageDirectory: AbsolutePath

    public init(storageDirectory: AbsolutePath) {
        self.init(fileSystem: FileSystem(), storageDirectory: storageDirectory)
    }

    init(fileSystem: FileSystem, storageDirectory: AbsolutePath) {
        self.fileSystem = fileSystem
        self.storageDirectory = storageDirectory
    }

    public func record(path: AbsolutePath) async throws {
        var content = try await read()
        content[path] = Date()
        try await write(content, storageDirectory: storageDirectory)
    }

    public func read() async throws -> [AbsolutePath: Date] {
        let recentPathsFile = recentPathsFile(storageDirectory: storageDirectory)
        guard try await fileSystem.exists(recentPathsFile) else { return [:] }
        return try await fileSystem.readJSONFile(at: recentPathsFile)
    }

    private func write(_ content: [AbsolutePath: Date], storageDirectory: AbsolutePath) async throws {
        try await fileSystem.writeAsJSON(content, at: recentPathsFile(storageDirectory: storageDirectory))
    }

    private func recentPathsFile(storageDirectory: AbsolutePath) -> AbsolutePath {
        storageDirectory.appending(component: "recent-paths.json")
    }
}
