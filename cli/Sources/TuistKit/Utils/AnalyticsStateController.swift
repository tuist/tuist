import FileSystem
import Foundation
import Path
import TuistCASAnalytics

/// Cleans up stale analytics state entries from the CAS analytics database
/// and the legacy file-based directories and `logs/` directory.
public struct AnalyticsStateController {
    private let fileSystem: FileSystem
    private let database: CASAnalyticsDatabasing?

    public init(fileSystem: FileSystem = FileSystem(), database: CASAnalyticsDatabasing? = nil) {
        self.fileSystem = fileSystem
        self.database = database ?? (try? CASAnalyticsDatabase.shared)
    }

    /// Schedules best-effort cleanup of old analytics state entries and legacy files.
    public func scheduleMaintenance(stateDirectory: AbsolutePath) {
        Task.detached(priority: .background) { [fileSystem, database] in
            try? await Self.clean(fileSystem: fileSystem, database: database, stateDirectory: stateDirectory)
        }
    }

    /// Removes analytics state entries older than `maxAge` and cleans up legacy directories.
    static func clean(
        fileSystem: FileSystem,
        database: CASAnalyticsDatabasing?,
        stateDirectory: AbsolutePath,
        maxAge: TimeInterval = 60 * 60
    ) async throws {
        let cutoffDate = Date().addingTimeInterval(-maxAge)

        try? database?.removeOldEntries(olderThan: cutoffDate)

        for directory in ["cas", "nodes"] {
            let directoryPath = stateDirectory.appending(component: directory)
            if try await fileSystem.exists(directoryPath) {
                try await fileSystem.remove(directoryPath)
            }
        }

        let keyValueDirectory = stateDirectory.appending(component: "keyvalue")
        if try await fileSystem.exists(keyValueDirectory) {
            try await fileSystem.remove(keyValueDirectory)
        }

        let logsDirectory = stateDirectory.appending(component: "logs")
        if try await fileSystem.exists(logsDirectory) {
            try await fileSystem.remove(logsDirectory)
        }
    }
}
