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
        let path: AbsolutePath = self.path(path)
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

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
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
            try FileHandler.shared.delete(dependenciesPath)
        }
        logger.info("Successfully cleaned dependencies at path \(dependenciesPath.pathString)", metadata: .success)
    }
}
