import FileSystem
import Foundation
import Path

public struct LogsCleaner {
    let fileSystem = FileSystem()

    public init() {}

    public func clean(logsDirectory: AbsolutePath) async throws {
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        for logPath in try await fileSystem.glob(directory: logsDirectory, include: ["*"]).collect() {
            if let creationDate = try FileManager.default.attributesOfItem(atPath: logPath.pathString)[.creationDate] as? Date,
               creationDate < fiveDaysAgo
            {
                try await fileSystem.remove(logPath)
            }
        }
    }
}
