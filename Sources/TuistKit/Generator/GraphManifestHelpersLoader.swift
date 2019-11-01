import Basic
import Foundation
import TuistSupport

protocol GraphManifestHelpersLoading: AnyObject {
    func compileHelpersModule(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> (modulePath: AbsolutePath?, cleanup: () throws -> Void)
}

final class GraphManifestHelpersLoader: GraphManifestHelpersLoading {
    func compileHelpersModule(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> (modulePath: AbsolutePath?, cleanup: () throws -> Void) {
        // Return early if the helper directory doesn't exist
        guard let tuistDirectory = FileHandler.shared.locateDirectoryTraversingParents(from: at, path: Constants.tuistFolderName) else {
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
            "-working-directory", temporaryDirectory.path.pathString,
        ]

        command.append(contentsOf: files.map { $0.pathString })

        try System.shared.runAndPrint(command)

        let cleanup = { try FileHandler.shared.delete(temporaryDirectory.path) }
        return (outputPath, cleanup)
    }
}
