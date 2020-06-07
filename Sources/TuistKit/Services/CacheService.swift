import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import TuistSupport

final class CacheService {
    /// Cache controller.
    private let cacheController: CacheControlling

    /// Generator Model Loader, used for getting the user config
    private let generatorModelLoader: GeneratorModelLoader

    init(cacheController: CacheControlling = CacheController(),
         manifestLoader: ManifestLoader = ManifestLoader(),
         manifestLinter: ManifestLinter = ManifestLinter()) {
        self.cacheController = cacheController
        generatorModelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                                    manifestLinter: manifestLinter)
    }

    func run(path: String?) throws {
        let path = self.path(path)
        let config = try generatorModelLoader.loadConfig(at: currentPath)
        try cacheController.cache(path: path, config: config)
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
