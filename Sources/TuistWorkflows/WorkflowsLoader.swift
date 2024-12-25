import Path
import FileSystem

/// A utility to load an in-memory representation of workflows.
public struct WorkflowsLoader {
    let fileSystem: FileSystem
    
    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }
    
    /// Given a workflows directory, the Workflows/ directory under Tuist/, it returns a in-memory
    /// list of all the workflows in that directory.
    /// - Parameter workflowsDirectory: The workflows directory where workflows as expected to be.
    /// - Returns: A list with all the workflows.
    public func load(workflowsDirectory: AbsolutePath) async throws -> [Workflow] {
        let files = try await fileSystem.glob(directory: workflowsDirectory, include: ["*.swift"]).collect()
        return files.map { filePath in
            return Workflow(path: filePath, name: filePath.basename.replacing(".swift", with: ""))
        }
    }
}
