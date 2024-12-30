import TuistCore
import Path
import FileSystem

public struct WorkflowsPackageSwiftLocator {
    let rootDirectoryLocator = RootDirectoryLocator()
    let fileSystem = FileSystem()
    
    func locate(from: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: from) else {
            return nil
        }
        
        let packageSwiftPath = rootDirectory.appending(try RelativePath(validating: "Tuist/Workflows/Package.swift"))
        if try await fileSystem.exists(packageSwiftPath) {
            return packageSwiftPath
        }
        
        return nil
    }
}
