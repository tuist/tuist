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
        let cacheDirectoryProvider = try cacheDirectoryProviderFactory.cacheDirectories(config: config)

        try categories.forEach {
            switch $0 {
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
        if let path = path {
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
        let dependenciesPath = path.appending(components: [Constants.tuistDirectoryName, Constants.DependenciesDirectory.name])
        if FileHandler.shared.exists(dependenciesPath) {
            let carthagePath = dependenciesPath.appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
            if FileHandler.shared.exists(carthagePath) {
                try FileHandler.shared.delete(carthagePath)
            }

            let spmPath = dependenciesPath.appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
            if FileHandler.shared.exists(spmPath) {
                try FileHandler.shared.delete(spmPath)
            }
        }
        logger.info("Successfully cleaned dependencies at path \(dependenciesPath.pathString)", metadata: .success)
    }
}
