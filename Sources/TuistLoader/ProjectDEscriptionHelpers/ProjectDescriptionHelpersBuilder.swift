import Foundation
import TSCBasic
import TuistSupport

/// This protocol defines the interface to compile a temporary module with the
/// helper files under /Tuist/ProjectDescriptionHelpers that can be imported
/// from any manifest being loaded.
protocol ProjectDescriptionHelpersBuilding: AnyObject {
    /// Builds the helpers module and returns it.
    /// - Parameters:
    ///   - at: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionPath: Path to the project description module.
    func build(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> AbsolutePath?
}

final class ProjectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding {
    /// A dictionary that keeps in memory the helpers (value of the dictionary) that have been built
    /// in the current process for helpers directories (key of the dictionary)
    fileprivate var builtHelpers: [AbsolutePath: AbsolutePath] = [:]

    /// Path to the cache directory.
    let cacheDirectory: AbsolutePath

    /// Instance to locate the helpers directory.
    let helpersDirectoryLocator: HelpersDirectoryLocating

    /// Project description helpers hasher.
    let projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing

    /// Initializes the builder with its attributes.
    /// - Parameters:
    ///   - projectDescriptionHelpersHasher: Project description helpers hasher.
    ///   - cacheDirectory: Path to the cache directory.
    ///   - helpersDirectoryLocating: Instance to locate the helpers directory.
    init(projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing = ProjectDescriptionHelpersHasher(),
         cacheDirectory: AbsolutePath = Environment.shared.projectDescriptionHelpersCacheDirectory,
         helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator())
    {
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.cacheDirectory = cacheDirectory
        self.helpersDirectoryLocator = helpersDirectoryLocator
    }

    func build(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> AbsolutePath? {
        guard let helpersDirectory = helpersDirectoryLocator.locate(at: at) else { return nil }
        if let cachedPath = builtHelpers[helpersDirectory] { return cachedPath }

        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: helpersDirectory)
        let prefixHash = projectDescriptionHelpersHasher.prefixHash(helpersDirectory: helpersDirectory)

        // Get paths
        let helpersCachePath = cacheDirectory.appending(component: prefixHash)
        let helpersModuleCachePath = helpersCachePath.appending(component: hash)
        let dylibName = "libProjectDescriptionHelpers.dylib"
        let modulePath = helpersModuleCachePath.appending(component: dylibName)

        builtHelpers[helpersDirectory] = modulePath

        if FileHandler.shared.exists(helpersModuleCachePath) {
            return modulePath
        }

        // If the same helpers directory has been previously compiled
        // we delete it before compiling the new changes.
        if FileHandler.shared.exists(helpersCachePath) {
            try FileHandler.shared.delete(helpersCachePath)
        }
        try FileHandler.shared.createFolder(helpersModuleCachePath)

        let command = self.command(outputDirectory: helpersModuleCachePath,
                                   helpersDirectory: helpersDirectory,
                                   projectDescriptionPath: projectDescriptionPath)
        try System.shared.runAndPrint(command, verbose: false, environment: Environment.shared.tuistVariables)

        return modulePath
    }

    // MARK: - Fileprivate

    fileprivate func command(outputDirectory: AbsolutePath,
                             helpersDirectory: AbsolutePath,
                             projectDescriptionPath: AbsolutePath) -> [String]
    {
        let files = FileHandler.shared.glob(helpersDirectory, glob: "**/*.swift")
        var command: [String] = [
            "/usr/bin/xcrun", "swiftc",
            "-module-name", "ProjectDescriptionHelpers",
            "-emit-module",
            "-emit-module-path", outputDirectory.appending(component: "ProjectDescriptionHelpers.swiftmodule").pathString,
            "-parse-as-library",
            "-emit-library",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.pathString,
            "-L", projectDescriptionPath.parentDirectory.pathString,
            "-F", projectDescriptionPath.parentDirectory.pathString,
            "-working-directory", outputDirectory.pathString,
        ]
        if projectDescriptionPath.extension == "dylib" {
            command.append(contentsOf: ["-lProjectDescription"])
        } else {
            command.append(contentsOf: ["-framework", "ProjectDescription"])
        }

        command.append(contentsOf: files.map { $0.pathString })
        return command
    }
}
