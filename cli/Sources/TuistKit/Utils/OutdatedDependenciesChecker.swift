import FileSystem
import Foundation
import Mockable
import Path
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistLoader
import TuistSupport

@Mockable
protocol OutdatedDependenciesChecking {
    func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool
}

struct OutdatedDependenciesChecker: OutdatedDependenciesChecking {
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming
    private let configLoader: ConfigLoading
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    init(
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        fileSystem: FileSysteming = FileSystem(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController()
    ) {
        self.manifestFilesLocator = manifestFilesLocator
        self.fileSystem = fileSystem
        self.configLoader = configLoader
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool {
        guard let packageManifestPath = try await manifestFilesLocator.locatePackageManifest(at: path) else {
            return false
        }

        let packageDirectory = packageManifestPath.parentDirectory
        let config = try await configLoader.loadConfig(path: path)
        let arguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
        let scratchDirectory = try swiftPackageManagerScratchDirectoryLocator.locate(
            packagePath: packageDirectory,
            arguments: arguments,
            environment: Environment.current.variables,
            workingDirectory: try await Environment.current.currentWorkingDirectory()
        )
        let currentPackageResolvedPath = packageDirectory
            .appending(component: Constants.SwiftPackageManager.packageResolvedName)
        let savedPackageResolvedPath = scratchDirectory.appending(components: [
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])

        var currentData: Data?
        if try await fileSystem.exists(currentPackageResolvedPath) {
            currentData = try await fileSystem.readFile(at: currentPackageResolvedPath)
        }

        var savedData: Data?
        if try await fileSystem.exists(savedPackageResolvedPath) {
            savedData = try await fileSystem.readFile(at: savedPackageResolvedPath)
        }

        if currentData != savedData { return true }

        // A toolchain update leaves the lockfile as is, but its compiler cannot import the recorded prebuilts.
        return try await swiftPackageManagerController.recordsOutdatedPrebuilts(
            at: packageDirectory,
            scratchDirectory: scratchDirectory
        )
    }
}
