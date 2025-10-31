import FileSystem
import Foundation
import Path
import TuistCore
import TuistDependencies
import TuistLoader
import TuistPlugin
import TuistSupport

final class InstallService {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let fileHandler: FileHandling
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(
            manifestLoader: CachedManifestLoader()
        ),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        fileHandler: FileHandling = FileHandler.shared,
        fileSystem: FileSysteming = FileSystem(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
        self.manifestFilesLocator = manifestFilesLocator
    }

    func run(
        path: String?,
        update: Bool,
        passthroughArguments: [String],
    ) async throws {
        let path = try self.path(path)

        try await fetchPlugins(path: path)
        try await fetchDependencies(path: path, update: update, passthroughArguments: passthroughArguments)
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: fileHandler.currentPath)
        } else {
            return fileHandler.currentPath
        }
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

        if update {
            Logger.current.notice("Updating dependencies.", metadata: .section)

            try swiftPackageManagerController.update(
                at: packageManifestPath.parentDirectory,
                arguments: mergedArguments,
                printOutput: true
            )
        } else {
            Logger.current.notice("Resolving and fetching dependencies.", metadata: .section)

            try swiftPackageManagerController.resolve(
                at: packageManifestPath.parentDirectory,
                arguments: mergedArguments,
                printOutput: true
            )
        }

        try await savePackageResolved(at: packageManifestPath.parentDirectory)
    }

    private func arguments(config: Tuist, passthroughArguments: [String]) -> [String] {
        let configArguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
        // Passthrough arguments come last so they override config arguments (last flag wins)
        return configArguments + passthroughArguments
    }

    private func savePackageResolved(at path: AbsolutePath) async throws {
        let sourcePath = path.appending(component: Constants.SwiftPackageManager.packageResolvedName)
        guard try await fileSystem.exists(sourcePath) else { return }

        let destinationPath = path.appending(components: [
            Constants.SwiftPackageManager.packageBuildDirectoryName,
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
