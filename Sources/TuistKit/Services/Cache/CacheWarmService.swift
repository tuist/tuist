import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport

final class CacheWarmService {
    /// Generator Model Loader, used for getting the user config
    private let generatorModelLoader: GeneratorModelLoader

    init(manifestLoader: ManifestLoader = ManifestLoader(),
         manifestLinter: ManifestLinter = ManifestLinter())
    {
        generatorModelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                                    manifestLinter: manifestLinter)
    }

    func run(path: String?) throws {
        let path = self.path(path)
        let config = try generatorModelLoader.loadConfig(at: currentPath)
        let cache = Cache(storageProvider: CacheStorageProvider(config: config))
        let cacheController = CacheController(cache: cache)
        try cacheController.cache(path: path)
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }
}
