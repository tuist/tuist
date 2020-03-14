import Basic
import Foundation
import TuistSupport

/// This protocol defines the interface to compile a temporary module with the
/// helper files under /Tuist/ProjectDescriptionHelpers that can be imported
/// from any manifest being loaded.
public protocol ProjectDescriptionHelpersBuilding: AnyObject {
    /// Builds the helpers module and returns it.
    /// - Parameters:
    ///   - at: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionPath: Path to the project description module.
    func build(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> AbsolutePath?
}

public final class ProjectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding {
    /// A dictionary that keeps in memory the helpers (value of the dictionary) that have been built
    /// in the current process for helpers directories (key of the dictionary)
    fileprivate var builtHelpers: [AbsolutePath: AbsolutePath] = [:]

    /// Path to the cache directory.
    let cacheDirectory: AbsolutePath

    /// Instance to locate the helpers directory.
    let helpersDirectoryLocator: HelpersDirectoryLocating

    /// Initializes the builder with its attributes.
    /// - Parameters:
    ///   - cacheDirectory: Path to the cache directory.
    ///   - helpersDirectoryLocating: Instance to locate the helpers directory.
    public init(cacheDirectory: AbsolutePath = Environment.shared.projectDescriptionHelpersCacheDirectory,
                helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator()) {
        self.cacheDirectory = cacheDirectory
        self.helpersDirectoryLocator = helpersDirectoryLocator
    }

    public func build(at: AbsolutePath, projectDescriptionPath: AbsolutePath) throws -> AbsolutePath? {
        guard let helpersDirectory = helpersDirectoryLocator.locate(at: at) else { return nil }
        if let cachedPath = builtHelpers[helpersDirectory] { return cachedPath }

        let hash = try self.hash(helpersDirectory: helpersDirectory)
        let prefixHash = self.prefixHash(helpersDirectory: helpersDirectory)

        // Get paths
        let helpersCachePath = cacheDirectory.appending(component: prefixHash)
        let helpersModuleCachePath = helpersCachePath.appending(component: hash)
        let dylibName = "libProjectDescriptionHelpers.dylib"

        if FileHandler.shared.exists(helpersModuleCachePath) {
            return helpersModuleCachePath.appending(component: dylibName)
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
        try System.shared.runAndPrint(command)

        let modulePath = helpersModuleCachePath.appending(component: dylibName)
        builtHelpers[helpersDirectory] = modulePath
        return modulePath
    }

    // MARK: - Fileprivate

    fileprivate func command(outputDirectory: AbsolutePath,
                             helpersDirectory: AbsolutePath,
                             projectDescriptionPath: AbsolutePath) -> [String] {
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

    /// This method returns a hash based on the content in the helpers directory
    /// and the Swift version used to compile the module.
    /// - Parameter helpersDirectory: Path to the helpers directory.
    fileprivate func hash(helpersDirectory: AbsolutePath) throws -> String {
        let fileHashes = FileHandler.shared
            .glob(helpersDirectory, glob: "**/*.swift")
            .compactMap { $0.sha256() }
            .compactMap { $0.compactMap { byte in String(format: "%02x", byte) }.joined() }
        let swiftVersion = try System.shared.swiftVersion() ?? ""
        let tuistVersion = Constants.version

        let identifiers = [swiftVersion, tuistVersion] + fileHashes

        return identifiers.joined(separator: "-").md5
    }

    /// Gets the prefix hash for the given helpers directory.
    /// This is useful to uniquely identify a helpers directory in the cache.
    /// - Parameter helpersDirectory: Path to the helpers directory.
    fileprivate func prefixHash(helpersDirectory: AbsolutePath) -> String {
        let pathString = helpersDirectory.pathString
        let index = pathString.index(pathString.startIndex, offsetBy: 7)
        return String(helpersDirectory.pathString.md5[..<index])
    }
}
