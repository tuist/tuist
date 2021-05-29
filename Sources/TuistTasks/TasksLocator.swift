import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Finds tasks.
public protocol TasksLocating {
    /// Returns paths to user-defined tasks.
    func locateTasks(at path: AbsolutePath) throws -> [AbsolutePath]
}

public final class TasksLocator: TasksLocating {
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func locateTasks(at path: AbsolutePath) throws -> [AbsolutePath] {
        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else { return [] }
        let tasksDirectory = rootDirectory.appending(
            components: Constants.tuistDirectoryName, Constants.tasksDirectoryName
        )
        guard FileHandler.shared.exists(tasksDirectory) else { return [] }
        return try FileHandler.shared.contentsOfDirectory(tasksDirectory)
            .filter { $0.extension == "swift" }
    }
}
