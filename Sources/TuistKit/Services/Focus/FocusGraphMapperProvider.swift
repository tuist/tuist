import Foundation
import TuistCache
import TuistCore

final class FocusGraphMapperProvider: GraphMapperProviding {
    private let defaultProvider: GraphMapperProviding
    private let cacheSources: Set<String>
    private let cache: Bool
    private let cacheOutputType: CacheOutputType
    private let contentHasher: ContentHashing

    init(contentHasher: ContentHashing,
         cache: Bool,
         cacheSources: Set<String>,
         cacheOutputType: CacheOutputType,
         defaultProvider: GraphMapperProviding = GraphMapperProvider())
    {
        self.contentHasher = contentHasher
        self.cacheSources = cacheSources
        self.cache = cache
        self.defaultProvider = defaultProvider
        self.cacheOutputType = cacheOutputType
    }

    func mapper(config: Config) -> GraphMapping {
        let defaultMapper = defaultProvider.mapper(config: config)

        // Cache
        var mappers: [GraphMapping] = []
        if cache {
            let cacheMapper = CacheMapper(config: config,
                                          cacheStorageProvider: CacheStorageProvider(config: config),
                                          sources: cacheSources,
                                          cacheOutputType: cacheOutputType,
                                          contentHasher: contentHasher)
            mappers.append(cacheMapper)
            mappers.append(CacheTreeShakingGraphMapper())
        }

        /// The default mapper is executed at the end because
        /// it ensures that the workspace is in sync with the content in the graph.
        mappers.append(defaultMapper)

        return SequentialGraphMapper(mappers)
    }
}
