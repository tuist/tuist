import TuistCore
import Path
import FileSystem

public struct WorkflowsDirectoryLocator {
    let rootDirectoryLocator = RootDirectoryLocator()
    
    func locate(from: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: from) else {
            return nil
        }
        return rootDirectory.appending(try RelativePath(validating: "Tuist/Workflows"))
    }
}
