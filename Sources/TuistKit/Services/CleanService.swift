import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

final class CleanService {
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    init(
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory()
    ) {
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
    }

    func run(
        categories: [CleanCategory],
        path: String?
    ) throws {
        let path: AbsolutePath = try self.path(path)
        let manifestLoaderFactory = ManifestLoaderFactory()
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        let config = try configLoader.loadConfig(path: path)
        let cacheDirectoryProvider = try cacheDirectoryProviderFactory.cacheDirectories()

        for category in categories {
            switch category {
            case let .global(cacheCategory):
                try cleanCacheCategory(
                    cacheCategory,
                    cacheDirectoryProvider: cacheDirectoryProvider
                )
            case .dependencies:
                try cleanDependencies(at: path)
            }
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func cleanCacheCategory(
        _ cacheCategory: CacheCategory,
        cacheDirectoryProvider: CacheDirectoriesProviding
    ) throws {
        let directory = cacheDirectoryProvider.cacheDirectory(for: cacheCategory)
        if FileHandler.shared.exists(directory) {
            try FileHandler.shared.delete(directory)
            logger.info("Successfully cleaned artifacts at path \(directory.pathString)", metadata: .success)
        }
    }

    private func cleanDependencies(at path: AbsolutePath) throws {
        let swiftPackageManagerBuildPath = path.appending(
            components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageBuildDirectoryName
        )
        if FileHandler.shared.exists(swiftPackageManagerBuildPath) {
            try FileHandler.shared.delete(swiftPackageManagerBuildPath)
        }
        logger.info(
            "Successfully cleaned Swift Package Manager dependencies at path \(swiftPackageManagerBuildPath.pathString)",
            metadata: .success
        )
    }
}
