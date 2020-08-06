import Foundation
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistSigning

/// It defines an interface for providing the mappers to be used for a specific configuration.
protocol GraphMapperProviding {
    /// Returns a list of mappers to be used for a specific configuration.
    /// - Parameter config: Project's configuration.
    func mapper(config: Config) -> GraphMapping
}

final class GraphMapperProvider: GraphMapperProviding {
    fileprivate let cache: Bool
    fileprivate let cacheSources: Set<String>

    init(cache: Bool = false, cacheSources: Set<String> = Set()) {
        self.cache = cache
        self.cacheSources = cacheSources
    }

    func mapper(config: Config) -> GraphMapping {
        SequentialGraphMapper(mappers(config: config))
    }

    func mappers(config: Config) -> [GraphMapping] {
        var mappers: [GraphMapping] = []

        // Cache
        if cache {
            let cacheMapper = CacheMapper(config: config,
                                          cacheStorageProvider: CacheStorageProvider(config: config),
                                          sources: cacheSources)
            mappers.append(cacheMapper)
        }

        return mappers
    }
}
