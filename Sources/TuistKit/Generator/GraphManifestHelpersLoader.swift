import Foundation
import Basic
import TuistCore

protocol GraphManifestHelpersLoading: AnyObject {
    func compileHelpersModule(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> (modulePath: AbsolutePath?, cleanup: () throws -> ())
}

final class GraphManifestHelpersLoader: GraphManifestHelpersLoading {
    
    // MARK: - Attributes
    
    let tuistDirectoryLocator: TuistDirectoryLocating
    let system: Systeming
    
    // MARK: - Init
    
    init(tuistDirectoryLocator: TuistDirectoryLocating = TuistDirectoryLocator(),
         system: Systeming = System()) {
        self.tuistDirectoryLocator = tuistDirectoryLocator
        self.system = system
    }
    
    func compileHelpersModule(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> (modulePath: AbsolutePath?, cleanup: () throws -> ()) {
        // Return early if the helper directory doesn't exist
        guard let tuistDirectory = tuistDirectoryLocator.locate(from: at) else {
            return (nil, {})
        }
        let helpersDirectory = tuistDirectory.appending(component: "ProjectDescriptionHelpers")
        if !FileHandler.shared.exists(helpersDirectory) {
            return (nil, {})
        }
        
        let files = FileHandler.shared.glob(helpersDirectory, glob: "**/*.swift")
        let temporaryDirectory = try TemporaryDirectory()
        let outputPath = temporaryDirectory.path.appending(component: "ProjectDescriptionHelpers.dylib")
        var command: [String] = [
            "/usr/bin/xcrun", "swiftc",
            "-module-name", "ProjectDescriptionHelpers",
            "-emit-module",
            "-emit-module-path", temporaryDirectory.path.appending(component: "ProjectDescriptionHelpers.swiftmodule").pathString,
            "-parse-as-library",
            "-emit-library",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.pathString,
            "-L", projectDescriptionPath.parentDirectory.pathString,
            "-F", projectDescriptionPath.parentDirectory.pathString,
            "-framework", projectDescriptionPath.basename.replacingOccurrences(of: ".framework", with: ""),
            "-working-directory", temporaryDirectory.path.pathString
        ]

        command.append(contentsOf: files.map({ $0.pathString }))
        
        try system.runAndPrint(command)
        
        let cleanup = { try FileHandler.shared.delete(temporaryDirectory.path) }
        return (outputPath, cleanup)
    }
}
