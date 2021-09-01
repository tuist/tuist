import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

/// This protocol defines the interface to compile a temporary module with the
/// helper files under /Tuist/xxxHelpers that can be imported
/// from any manifest being loaded.
public protocol HelpersBuilding: AnyObject {
    /// Builds **all** the project description helpers module and returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionPath: Path to the project description module.
    ///   - projectDescriptionHelperPlugins: List of custom project description helper plugins to include and build.
    func buildProjectDescriptionHelpers(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) throws -> [HelpersModule]
    
    /// Builds **all** the project automation helpers module and returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the manifest being loaded.
    ///   - projectAutomationPath: Path to the project automation module.
    func buildProjectAutomationHelpers(
        at path: AbsolutePath,
        projectAutomationSearchPaths: ModuleSearchPaths
    ) throws -> [HelpersModule]

    /// Builds **only** the plugin helpers module and returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the manifest being loaded.
    ///   - projectDescriptionPath: Path to the project description module.
    ///   - projectDescriptionHelperPlugins: List of custom project description helper plugins to include and build.
    func buildPlugins(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) throws -> [HelpersModule]
}

public final class HelpersBuilder: HelpersBuilding {
    /// A dictionary that keeps in memory the helpers (value of the dictionary) that have been built
    /// in the current process for helpers directories (key of the dictionary)
    private var builtHelpers: [AbsolutePath: HelpersModule] = [:]

    /// Path to the cache directory.
    let cacheDirectory: AbsolutePath

    /// Instance to locate the helpers directory.
    let helpersDirectoryLocator: HelpersDirectoryLocating

    /// Project description helpers hasher.
    let projectDescriptionHelpersHasher: HelpersHashing

    /// Initializes the builder with its attributes.
    /// - Parameters:
    ///   - projectDescriptionHelpersHasher: Project description helpers hasher.
    ///   - cacheDirectory: Path to the cache directory.
    ///   - helpersDirectoryLocating: Instance to locate the helpers directory.
    public init(
        projectDescriptionHelpersHasher: HelpersHashing = HelpersHasher(),
        cacheDirectory: AbsolutePath,
        helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator()
    ) {
        self.projectDescriptionHelpersHasher = projectDescriptionHelpersHasher
        self.cacheDirectory = cacheDirectory
        self.helpersDirectoryLocator = helpersDirectoryLocator
    }

    public func buildProjectDescriptionHelpers(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) throws -> [HelpersModule] {
        let pluginHelpers = try buildPlugins(
            at: path,
            projectDescriptionSearchPaths: projectDescriptionSearchPaths,
            projectDescriptionHelperPlugins: projectDescriptionHelperPlugins
        )

        let defaultHelpers = try buildDefaultProjectDescriptionHelpers(
            in: path,
            projectDescriptionSearchPaths: projectDescriptionSearchPaths,
            customProjectDescriptionHelperModules: pluginHelpers
        )

        guard let builtDefaultHelpers = defaultHelpers else { return pluginHelpers }

        return [builtDefaultHelpers] + pluginHelpers
    }
    
    public func buildProjectAutomationHelpers(
        at path: AbsolutePath,
        projectAutomationSearchPaths: ModuleSearchPaths
    ) throws -> [HelpersModule] {
        let defaultHelpers = try buildDefaultProjectAutomationHelpers(
            in: path,
            projectAutomationSearchPaths: projectAutomationSearchPaths
        )
        
        guard let builtDefaultHelpers = defaultHelpers else { return [] }
        
        return [builtDefaultHelpers]
    }

    public func buildPlugins(
        at _: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) throws -> [HelpersModule] {
        let pluginHelpers = try projectDescriptionHelperPlugins.map {
            try buildHelpers(name: $0.name, in: $0.path, moduleSearchPaths: projectDescriptionSearchPaths)
        }

        return pluginHelpers
    }
    
    // MARK: - Helpers
    
    private func buildDefaultProjectAutomationHelpers(
        in path: AbsolutePath,
        projectAutomationSearchPaths: ModuleSearchPaths
    ) throws -> HelpersModule? {
        guard let tuistHelpersDirectory = helpersDirectoryLocator.locateProjectAutomationHelpers(at: path) else { return nil }
        return try buildHelpers(
            name: Constants.projectAutomationHelpersDirectoryName,
            in: tuistHelpersDirectory,
            moduleSearchPaths: projectAutomationSearchPaths
        )
    }

    private func buildDefaultProjectDescriptionHelpers(
        in path: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        customProjectDescriptionHelperModules: [HelpersModule]
    ) throws -> HelpersModule? {
        guard let tuistHelpersDirectory = helpersDirectoryLocator.locateProjectDescriptionHelpers(at: path) else { return nil }
        return try buildHelpers(
            name: Constants.projectDescriptionHelpersDirectoryName,
            in: tuistHelpersDirectory,
            moduleSearchPaths: projectDescriptionSearchPaths,
            customProjectDescriptionHelperModules: customProjectDescriptionHelperModules
        )
    }

    /// Builds the `ProjectDescription` helper with the given name at the given path.
    ///
    /// - Parameters:
    ///   - name: The name of the helper.
    ///   - path: The path for the helper.
    ///   - projectDescriptionSearchPaths: The search paths for `ProjectDescription`.
    ///   - customProjectDescriptionHelperModules: Any extra helper modules that should be included when building the given helper.
    ///
    /// - Note:
    ///   `customProjectDescriptionHelperModules` should be already built modules without a dependency on this module being built.
    ///
    /// - Throws: An error if unable to build the helper.
    /// - Returns: A built helpers modules.
    private func buildHelpers(
        name: String,
        in path: AbsolutePath,
        moduleSearchPaths: ModuleSearchPaths,
        customProjectDescriptionHelperModules: [HelpersModule] = []
    ) throws -> HelpersModule {
        if let cachedModule = builtHelpers[path] { return cachedModule }

        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: path)
        let prefixHash = projectDescriptionHelpersHasher.prefixHash(helpersDirectory: path)

        let helpersCachePath = cacheDirectory.appending(component: prefixHash)
        let helpersModuleCachePath = helpersCachePath.appending(component: hash)
        let dylibName = "lib\(name).dylib"
        let modulePath = helpersModuleCachePath.appending(component: dylibName)
        let projectDescriptionHelpersModule = HelpersModule(name: name, path: modulePath)

        builtHelpers[path] = projectDescriptionHelpersModule

        if FileHandler.shared.exists(helpersModuleCachePath) {
            return projectDescriptionHelpersModule
        }

        // If the same helpers directory has been previously compiled
        // we delete it before compiling the new changes.
        if FileHandler.shared.exists(helpersCachePath) {
            try FileHandler.shared.delete(helpersCachePath)
        }

        try FileHandler.shared.createFolder(helpersModuleCachePath)

        let command = createCommand(
            moduleName: name,
            directory: path,
            outputDirectory: helpersModuleCachePath,
            moduleSearchPaths: moduleSearchPaths,
            customProjectDescriptionHelperModules: customProjectDescriptionHelperModules
        )

        try System.shared.runAndPrint(command, verbose: false, environment: Environment.shared.manifestLoadingVariables)

        return projectDescriptionHelpersModule
    }

    private func createCommand(
        moduleName: String,
        directory: AbsolutePath,
        outputDirectory: AbsolutePath,
        moduleSearchPaths: ModuleSearchPaths,
        customProjectDescriptionHelperModules: [HelpersModule] = []
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
            "-I", moduleSearchPaths.includeSearchPath.pathString,
            "-L", moduleSearchPaths.librarySearchPath.pathString,
            "-F", moduleSearchPaths.frameworkSearchPath.pathString,
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

        if moduleSearchPaths.path.extension == "dylib" {
            command.append(contentsOf: ["-l\(moduleSearchPaths.path.basenameWithoutExt)"])
        } else {
            command.append(contentsOf: ["-framework", moduleSearchPaths.path.basenameWithoutExt])
        }

        command.append(contentsOf: files.map(\.pathString))
        return command
    }
}
