import FileSystem
import Foundation
import Mockable
import Path
import TuistConstants
import TuistLoader

@Mockable
protocol OutdatedDependenciesChecking {
    func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool
}

struct OutdatedDependenciesChecker: OutdatedDependenciesChecking {
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming

    init(
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.manifestFilesLocator = manifestFilesLocator
        self.fileSystem = fileSystem
    }

    func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool {
        guard let packageManifestPath = try await manifestFilesLocator.locatePackageManifest(at: path) else {
            return false
        }

        let packageDirectory = packageManifestPath.parentDirectory
        let currentPackageResolvedPath = packageDirectory
            .appending(component: Constants.SwiftPackageManager.packageResolvedName)
        let savedPackageResolvedPath = packageDirectory.appending(components: [
            Constants.SwiftPackageManager.packageBuildDirectoryName,
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

        return currentData != savedData
    }
}
