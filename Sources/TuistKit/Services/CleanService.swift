import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

final class CleanService {
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    init(
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory())
    {
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
    }

    func run(categories: [CacheCategory]) throws {
        let path: AbsolutePath = FileHandler.shared.currentPath
        let manifestLoaderFactory = ManifestLoaderFactory()
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        let config = try configLoader.loadConfig(path: path)
        let cacheDirectoryProvider = try cacheDirectoryProviderFactory.cacheDirectories(config: config)

        for category in categories {
            let directory = cacheDirectoryProvider.cacheDirectory(for: category)
            if FileHandler.shared.exists(directory) {
                try FileHandler.shared.delete(directory)
                logger.info("Successfully cleaned artifacts at path \(directory.pathString)", metadata: .success)
            }
        }
    }
}
