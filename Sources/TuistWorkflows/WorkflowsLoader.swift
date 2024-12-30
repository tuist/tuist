import Path
import FileSystem
import Command
import SwiftyJSON

/// A utility to load an in-memory representation of workflows.
public struct WorkflowsLoader {
    let fileSystem: FileSystem = FileSystem()
    let workflowsPackageSwiftLocator = WorkflowsPackageSwiftLocator()
    let commandRunner = CommandRunner()
    
    public init() {}
    
    public func load(from: AbsolutePath) async throws -> [Workflow] {
        guard let packageSwiftPath = try await workflowsPackageSwiftLocator.locate(from: from) else {
            return []
        }
    
        let packageString = try await commandRunner.run(arguments: ["/usr/bin/env", "swift", "package", "dump-package"], workingDirectory: packageSwiftPath.parentDirectory).concatenatedString()
        let packageJSON = JSON(parseJSON: packageString)

        guard let products = packageJSON["products"].array else { return [] }
        return await products.concurrentCompactMap { product -> Workflow? in
            guard let name = product["name"].string else { return nil }
            guard product["type"].dictionary?.keys.contains("executable") == true else { return nil }
            
            try? await commandRunner.run(arguments: ["/usr/bin/env", "swift", "build", "--package-path", packageSwiftPath.parentDirectory.pathString, "--product", name]).awaitCompletion()
            
            let dumpString = try? await commandRunner.run(arguments: [packageSwiftPath.parentDirectory.appending(components: [".build", "debug", name]).pathString, "--experimental-dump-help"], workingDirectory: packageSwiftPath.parentDirectory).concatenatedString()
            
            let description: String? = if let dumpString = dumpString, let abstract = JSON(parseJSON: dumpString)["command"]["abstract"].string {
                abstract
            } else {
                nil
            }
            
            return Workflow(packageSwiftPath: packageSwiftPath, name: name, description: description)
        }
    }
}
