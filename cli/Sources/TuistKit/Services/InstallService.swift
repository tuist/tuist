import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistDependencies
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistPlugin
import TuistSupport

@Mockable
protocol InstallServicing {
    func run(
        path: String?,
        update: Bool,
        passthroughArguments: [String]
    ) async throws
}

struct InstallService: InstallServicing {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
        self.fileSystem = fileSystem
        self.manifestFilesLocator = manifestFilesLocator
    }

    func run(
        path: String?,
        update: Bool,
        passthroughArguments: [String]
    ) async throws {
        let path = try await self.path(path)

        try await fetchPlugins(path: path)
        try await fetchDependencies(path: path, update: update, passthroughArguments: passthroughArguments)
    }

    // MARK: - Helpers

    private func path(_ path: String?) async throws -> AbsolutePath {
        try await Environment.current.pathRelativeToWorkingDirectory(path)
    }

    private func fetchPlugins(path: AbsolutePath) async throws {
        Logger.current.notice("Resolving and fetching plugins.", metadata: .section)

        let config = try await configLoader.loadConfig(path: path)
        if let generatedProjectOptions = config.project.generatedProject {
            _ = try await pluginService.loadPlugins(using: generatedProjectOptions)
        }

        AlertController.current.success(.alert("Plugins resolved and fetched successfully."))
    }

    private func fetchDependencies(path: AbsolutePath, update: Bool, passthroughArguments: [String]) async throws {
        guard let packageManifestPath = try await manifestFilesLocator.locatePackageManifest(at: path)
        else {
            return
        }

        let config = try await configLoader.loadConfig(path: path)

        let mergedArguments = arguments(config: config, passthroughArguments: passthroughArguments)
        let scratchDirectory = try await swiftPackageManagerScratchDirectory(
            packagePath: packageManifestPath.parentDirectory,
            arguments: mergedArguments
        )

        if update {
            Logger.current.notice("Updating dependencies.", metadata: .section)

            try await swiftPackageManagerController.update(
                at: packageManifestPath.parentDirectory,
                arguments: mergedArguments,
                printOutput: true
            )
        } else {
            Logger.current.notice("Resolving and fetching dependencies.", metadata: .section)

            try await swiftPackageManagerController.resolve(
                at: packageManifestPath.parentDirectory,
                arguments: mergedArguments,
                printOutput: true
            )
        }

        try await savePackageResolved(
            at: packageManifestPath.parentDirectory,
            scratchDirectory: scratchDirectory
        )
    }

    private func arguments(config: Tuist, passthroughArguments: [String]) -> [String] {
        let configArguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
        // Passthrough arguments come last so duplicate SwiftPM options can be overridden by the command line.
        return configArguments + passthroughArguments
    }

    private func swiftPackageManagerScratchDirectory(
        packagePath: AbsolutePath,
        arguments: [String]
    ) async throws -> AbsolutePath {
        try swiftPackageManagerScratchDirectoryLocator.locate(
            packagePath: packagePath,
            arguments: arguments,
            environment: Environment.current.variables,
            workingDirectory: try await Environment.current.currentWorkingDirectory()
        )
    }

    private func savePackageResolved(
        at path: AbsolutePath,
        scratchDirectory: AbsolutePath
    ) async throws {
        let sourcePath = path.appending(component: Constants.SwiftPackageManager.packageResolvedName)
        guard try await fileSystem.exists(sourcePath) else { return }

        let destinationPath = scratchDirectory.appending(components: [
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])
        if try await !fileSystem.exists(destinationPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: destinationPath.parentDirectory)
        }
        if try await fileSystem.exists(destinationPath) {
            try await fileSystem.remove(destinationPath)
        }
        try await fileSystem.copy(sourcePath, to: destinationPath)
    }
}
