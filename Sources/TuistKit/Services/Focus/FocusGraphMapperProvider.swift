import Foundation
import TuistCache
import TuistCore

final class FocusGraphMapperProvider: GraphMapperProviding {
    private let defaultProvider: GraphMapperProviding
    private let cacheSources: Set<String>
    private let cache: Bool
    private let cacheOutputType: CacheOutputType

    init(cache: Bool,
         cacheSources: Set<String>,
         cacheOutputType: CacheOutputType,
         defaultProvider: GraphMapperProviding = GraphMapperProvider())
    {
        self.cacheSources = cacheSources
        self.cache = cache
        self.defaultProvider = defaultProvider
        self.cacheOutputType = cacheOutputType
    }

    func mapper(config: Config) -> GraphMapping {
        let defaultMapper = defaultProvider.mapper(config: config)

        // Cache
        var mappers: [GraphMapping] = [defaultMapper]
        if cache {
            let cacheMapper = CacheMapper(config: config,
                                          cacheStorageProvider: CacheStorageProvider(config: config),
                                          sources: cacheSources,
                                          cacheOutputType: cacheOutputType)
            mappers.append(cacheMapper)
            mappers.append(CacheTreeShakingGraphMapper())
        }

        return SequentialGraphMapper(mappers)
    }
}
