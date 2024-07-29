import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport

/// This protocol defines the interface to compile a temporary module with the
/// helper files under /Tuist/ProjectDescriptionHelpers that can be imported
/// from any manifest being loaded.
public protocol ProjectDescriptionHelpersBuilding: AnyObject {
    /// Builds all the project description helpers incluing any `projectDescriptionHelperPlugins`.
    ///
    /// Note: Local project description helpers can import plugin helpers.
    /// We build the plugin modules first to allow including them in the local helper modules.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionSearchPaths: Path to the project description module.
    ///   - projectDescriptionHelperPlugins: List of custom project description helper plugins to include and build.
    func build(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        projectDescriptionHelperPlugins: [TuistCore.ProjectDescriptionHelpersPlugin]
    ) async throws -> [ProjectDescriptionHelpersModule]

    /// Builds all the plugin helpers module and returns the location to the built modules.
    ///
    /// Unlike local helper modules, plugins cannot include or depend on local helper modules.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionPath: Path to the project description module.
    ///   - projectDescriptionHelperPlugins: List of custom project description helper plugins to include and build.
    func buildPlugins(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) async throws -> [ProjectDescriptionHelpersModule]
}

public final class ProjectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding {
    /// A dictionary that keeps in memory the helpers (value of the dictionary) that have been built
    /// in the current process for helpers directories (key of the dictionary)
    private var builtHelpers: ThreadSafe<[AbsolutePath: ProjectDescriptionHelpersModule]> = ThreadSafe([:])

    /// Path to the cache directory.
    private let cacheDirectory: AbsolutePath

    /// Instance to locate the helpers directory.
    private let helpersDirectoryLocator: HelpersDirectoryLocating

    /// Project description helpers hasher.
    private let projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing

    /// Clock for measuring build duration.
    private let clock: Clock
    private let fileSystem: FileSystem

    /// The name of the default project description helpers module
    static let defaultHelpersName = "ProjectDescriptionHelpers"

    /// Initializes the builder with its attributes.
    /// - Parameters:
    ///   - projectDescriptionHelpersHasher: Project description helpers hasher.
    ///   - cacheDirectory: Path to the cache directory.
    ///   - helpersDirectoryLocator: Instance to locate the helpers directory.
    ///   - clock: Clock for measuring build duration.
    public init(
        projectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing = ProjectDescriptionHelpersHasher(),
        cacheDirectory: AbsolutePath,
        helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator(),
        clock: Clock = WallClock(),
        fileSystem: FileSystem = FileSystem()
    ) {
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.cacheDirectory = cacheDirectory
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.clock = clock
        self.fileSystem = fileSystem
    }

    public func build(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) async throws -> [ProjectDescriptionHelpersModule] {
        let pluginHelpers = try await buildPlugins(
            at: path,
            projectDescriptionSearchPaths: projectDescriptionSearchPaths,
            projectDescriptionHelperPlugins: projectDescriptionHelperPlugins
        )

        let defaultHelpers = try await buildDefaultHelpers(
            in: path,
            projectDescriptionSearchPaths: projectDescriptionSearchPaths,
            customProjectDescriptionHelperModules: pluginHelpers
        )

        guard let builtDefaultHelpers = defaultHelpers else { return pluginHelpers }

        return [builtDefaultHelpers] + pluginHelpers
    }

    public func buildPlugins(
        at _: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) async throws -> [ProjectDescriptionHelpersModule] {
        return try await projectDescriptionHelperPlugins.concurrentMap { plugin in
            try await self.buildHelpers(
                name: plugin.name,
                in: plugin.path,
                projectDescriptionSearchPaths: projectDescriptionSearchPaths
            )
        }
    }

    private func buildDefaultHelpers(
        in path: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        customProjectDescriptionHelperModules: [ProjectDescriptionHelpersModule]
    ) async throws -> ProjectDescriptionHelpersModule? {
        guard let tuistHelpersDirectory = helpersDirectoryLocator.locate(at: path) else { return nil }
        #if DEBUG
            if let sourceRoot = ProcessInfo.processInfo.environment["TUIST_CONFIG_SRCROOT"],
               tuistHelpersDirectory.isDescendant(
                   // swiftlint:disable:next force_try
                   of: try! AbsolutePath(validating: sourceRoot).appending(component: Constants.tuistDirectoryName)
               )
            {
                return nil
            }
        #endif
        return try await buildHelpers(
            name: Self.defaultHelpersName,
            in: tuistHelpersDirectory,
            projectDescriptionSearchPaths: projectDescriptionSearchPaths,
            customProjectDescriptionHelperModules: customProjectDescriptionHelperModules
        )
    }

    /// Builds the `ProjectDescription` helper with the given name at the given path.
    ///
    /// - Parameters:
    ///   - name: The name of the helper.
    ///   - path: The path for the helper.
    ///   - projectDescriptionSearchPaths: The search paths for `ProjectDescription`.
    ///   - customProjectDescriptionHelperModules: Any extra helper modules that should be included when building the given
    /// helper.
    ///
    /// - Note:
    ///   `customProjectDescriptionHelperModules` should be already built modules without a dependency on this module being built.
    ///
    /// - Throws: An error if unable to build the helper.
    /// - Returns: A built helpers modules.
    private func buildHelpers(
        name: String,
        in path: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        customProjectDescriptionHelperModules: [ProjectDescriptionHelpersModule] = []
    ) async throws -> ProjectDescriptionHelpersModule {
        if let cachedModule = builtHelpers.withValue({ $0[path] }) { return cachedModule }

        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: path)
        let prefixHash = projectDescriptionHelpersHasher.prefixHash(helpersDirectory: path)

        let helpersCachePath = cacheDirectory.appending(component: prefixHash)
        let helpersModuleCachePath = helpersCachePath.appending(component: hash)
        let dylibName = "lib\(name).dylib"
        let modulePath = helpersModuleCachePath.appending(component: dylibName)
        let projectDescriptionHelpersModule = ProjectDescriptionHelpersModule(name: name, path: modulePath)

        builtHelpers.mutate { $0[path] = projectDescriptionHelpersModule }

        if FileHandler.shared.exists(helpersModuleCachePath) {
            return projectDescriptionHelpersModule
        }

        try FileHandler.shared.createFolder(helpersModuleCachePath)

        let command = createCommand(
            moduleName: name,
            directory: path,
            outputDirectory: helpersModuleCachePath,
            projectDescriptionSearchPaths: projectDescriptionSearchPaths,
            customProjectDescriptionHelperModules: customProjectDescriptionHelperModules
        )

        let timer = clock.startTimer()
        try System.shared.runAndPrint(command, verbose: false, environment: Environment.shared.manifestLoadingVariables)
        let duration = timer.stop()
        let time = String(format: "%.3f", duration)
        logger.debug("Built \(name) in (\(time)s)", metadata: .success)

        return projectDescriptionHelpersModule
    }

    private func createCommand(
        moduleName: String,
        directory: AbsolutePath,
        outputDirectory: AbsolutePath,
        projectDescriptionSearchPaths: ProjectDescriptionSearchPaths,
        customProjectDescriptionHelperModules: [ProjectDescriptionHelpersModule] = []
    ) -> [String] {
        let swiftFilesGlob = "**/*.swift"
        let files = FileHandler.shared.glob(directory, glob: swiftFilesGlob)

        var command: [String] = [
            "/usr/bin/xcrun", "swiftc",
            "-module-name", moduleName,
            "-emit-module",
            "-emit-module-path", outputDirectory.appending(component: "\(moduleName).swiftmodule").pathString,
            "-parse-as-library",
            "-emit-library",
            "-suppress-warnings",
            "-I", projectDescriptionSearchPaths.includeSearchPath.pathString,
            "-L", projectDescriptionSearchPaths.librarySearchPath.pathString,
            "-F", projectDescriptionSearchPaths.frameworkSearchPath.pathString,
            "-working-directory", outputDirectory.pathString,
        ]

        let helperModuleCommands = customProjectDescriptionHelperModules
            .flatMap { [
                "-I", $0.path.parentDirectory.pathString,
                "-L", $0.path.parentDirectory.pathString,
                "-F", $0.path.parentDirectory.pathString,
                "-l\($0.name)",
            ] }

        command.append(contentsOf: helperModuleCommands)

        if projectDescriptionSearchPaths.path.extension == "dylib" {
            command.append(contentsOf: ["-lProjectDescription"])
        } else {
            command.append(contentsOf: ["-framework", "ProjectDescription"])
        }

        command.append(contentsOf: files.map(\.pathString))
        return command
    }
}
