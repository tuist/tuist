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

    init(
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        fileSystem: FileSysteming = FileSystem(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator()
    ) {
        self.manifestFilesLocator = manifestFilesLocator
        self.fileSystem = fileSystem
        self.configLoader = configLoader
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
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
        return try await hasPrunedCacheLinks(scratchDirectory: scratchDirectory)
    }

    /// SwifterPM links checkouts, binary artifacts and registry downloads into the shared cache,
    /// which drops entries nothing has used for a while. A project nobody installed in since then
    /// still matches its `Package.resolved` but links to nothing, so it needs `tuist install`.
    private func hasPrunedCacheLinks(scratchDirectory: AbsolutePath) async throws -> Bool {
        let links = try await entries(in: scratchDirectory.appending(component: "checkouts"), depth: 1)
            + entries(in: scratchDirectory.appending(component: "artifacts"), depth: 2)
            + entries(in: scratchDirectory.appending(components: "registry", "downloads"), depth: 3)
            .map { $0.appending(component: Constants.SwiftPackageManager.packageSwiftName) }
        for link in links where !link.basename.hasPrefix(".") {
            // `exists` follows symbolic links, so a link whose cache entry is gone reads as absent.
            if try await !fileSystem.exists(link) { return true }
        }
        return false
    }

    private func entries(in directory: AbsolutePath, depth: Int) async throws -> [AbsolutePath] {
        guard try await fileSystem.exists(directory, isDirectory: true) else { return [] }
        let children = try await fileSystem.contentsOfDirectory(directory)
            .filter { !$0.basename.hasPrefix(".") }
        guard depth > 1 else { return children }
        var entries: [AbsolutePath] = []
        for child in children {
            entries += try await self.entries(in: child, depth: depth - 1)
        }
        return entries
    }
}
