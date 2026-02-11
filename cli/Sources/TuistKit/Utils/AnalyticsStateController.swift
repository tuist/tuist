import FileSystem
import Foundation
import Path

/// Cleans up stale analytics state directories (`cas/`, `keyvalue/`, `nodes/`)
/// and the legacy `logs/` directory from the CLI state directory.
public struct AnalyticsStateController {
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Schedules best-effort cleanup of old analytics state files and legacy logs.
    public func scheduleMaintenance(stateDirectory: AbsolutePath) {
        Task.detached(priority: .background) { [fileSystem] in
            try? await Self.clean(fileSystem: fileSystem, stateDirectory: stateDirectory)
        }
    }

    /// Removes analytics state files older than `maxAge` and deletes the legacy `logs/` directory.
    static func clean(
        fileSystem: FileSystem,
        stateDirectory: AbsolutePath,
        maxAge: TimeInterval = 60 * 60
    ) async throws {
        let analyticsDirectories = ["cas", "nodes"]
        for directory in analyticsDirectories {
            let directoryPath = stateDirectory.appending(component: directory)
            try await removeOldFiles(
                fileSystem: fileSystem,
                directory: directoryPath,
                include: ["*"],
                maxAge: maxAge
            )
        }

        let keyValueDirectory = stateDirectory.appending(component: "keyvalue")
        for subdirectory in ["read", "write"] {
            let subdirectoryPath = keyValueDirectory.appending(component: subdirectory)
            try await removeOldFiles(
                fileSystem: fileSystem,
                directory: subdirectoryPath,
                include: ["*"],
                maxAge: maxAge
            )
        }

        let logsDirectory = stateDirectory.appending(component: "logs")
        if try await fileSystem.exists(logsDirectory) {
            try await fileSystem.remove(logsDirectory)
        }
    }

    private static func removeOldFiles(
        fileSystem: FileSystem,
        directory: AbsolutePath,
        include: [String],
        maxAge: TimeInterval
    ) async throws {
        guard try await fileSystem.exists(directory) else { return }

        let cutoffDate = Date().addingTimeInterval(-maxAge)

        for filePath in try await fileSystem.glob(directory: directory, include: include).collect() {
            guard let creationDate = try FileManager.default.attributesOfItem(
                atPath: filePath.pathString
            )[.creationDate] as? Date else { continue }

            if creationDate < cutoffDate {
                try await fileSystem.remove(filePath)
            }
        }
    }
}
