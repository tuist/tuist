import Basic
import Foundation
import TuistSupport

/// This struct represents a project description helpers
/// module that has been created temporarily to load the manifests.
class ProjectDescriptionHelpersModule {
    /// Path to the module.
    let path: AbsolutePath

    /// Function to clean up the temporary module.
    let cleanup: () throws -> Void

    /// Initializes an instance with the given attributes.
    /// - Parameters:
    ///   - path: Path to the module.
    ///   - cleanup: Function to clean up the temporary module.
    init(path: AbsolutePath, cleanup: @escaping () throws -> Void) {
        self.path = path
        self.cleanup = cleanup
    }

    deinit {
        try? cleanup()
    }
}

/// This protocol defines the interface to compile a temporary module with the
/// helper files under /Tuist/ProjectDescriptionHelpers that can be imported
/// from any manifest being loaded.
protocol ProjectDescriptionHelpersBuilding: AnyObject {
    /// Builds the helpers module and returns it.
    /// - Parameters:
    ///   - at: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionPath: Path to the project description module.
    func build(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> ProjectDescriptionHelpersModule?
}

final class ProjectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding {
    /// Instance to locate the root directory of the project.
    let rootDirectoryLocator: RootDirectoryLocating

    /// Initializes the builder with its attributes.
    /// - Parameter rootDirectoryLocator: Instance to locate the root directory of the project.
    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    func build(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> ProjectDescriptionHelpersModule? {
        // We return if the helpers directory doesn't exist at /Tuist/ProjectDesciptionHelpers
        guard let rootDirectory = self.rootDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.helpersDirectoryName)
        if !FileHandler.shared.exists(helpersDirectory) { return nil }

        let files = FileHandler.shared.glob(helpersDirectory, glob: "**/*.swift")
        let temporaryDirectory = try TemporaryDirectory()
        let outputPath = temporaryDirectory.path.appending(component: "libProjectDescriptionHelpers.dylib")
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
            "-working-directory", temporaryDirectory.path.pathString,
        ]
        if projectDescriptionPath.basename.contains("dylib") {
            command.append(contentsOf: ["-lProjectDescription"])
        } else {
            command.append(contentsOf: ["-framework", "ProjectDescription"])
        }

        command.append(contentsOf: files.map { $0.pathString })

        try System.shared.runAndPrint(command)

        let cleanup = { try FileHandler.shared.delete(temporaryDirectory.path) }
        return ProjectDescriptionHelpersModule(path: outputPath, cleanup: cleanup)
    }
}
