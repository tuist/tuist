import Foundation
import TuistCache
import TuistCore

/// It defines an interface for providing the mappers to be used for a specific configuration.
protocol GraphMapperProviding {
    /// Returns a list of mappers to be used for a specific configuration.
    /// - Parameter config: Project's configuration.
    func mapper(config: Config) -> GraphMapping
}

final class GraphMapperProvider: GraphMapperProviding {
    fileprivate let useCache: Bool

    init(useCache: Bool) {
        self.useCache = useCache
    }

    func mapper(config: Config) -> GraphMapping {
        SequentialGraphMapper(mappers(config: config))
    }

    func mappers(config _: Config) -> [GraphMapping] {
        var mappers: [GraphMapping] = []

        // Cache
        if useCache {
            mappers.append(CacheMapper())
        }

        return mappers
    }
}
