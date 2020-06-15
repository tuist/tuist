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
    fileprivate let useCache: Bool

    init(useCache: Bool) {
        self.useCache = useCache
    }

    func mapper(config: Config) -> GraphMapping {
        SequentialGraphMapper(mappers(config: config))
    }

    func mappers(config: Config) -> [GraphMapping] {
        var mappers: [GraphMapping] = []

        // Cache
        if useCache {
            mappers.append(CacheMapper(config: config))
        }

        // Cloud
        if let cloud = config.cloud, cloud.options.contains(.insights) {
            mappers.append(CloudInsightsGraphMapper())
        }

        return mappers
    }
}
