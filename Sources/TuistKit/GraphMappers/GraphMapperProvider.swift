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
    
    init(cache: Bool = false) {
        self.cache = cache
    }

    func mapper(config: Config) -> GraphMapping {
        SequentialGraphMapper(mappers(config: config))
    }

    func mappers(config: Config) -> [GraphMapping] {
        var mappers: [GraphMapping] = []

        // Cache
        if self.cache {
            mappers.append(CacheMapper(config: config, cloudClient: CloudClient()))
        }

        // Cloud
        if let cloud = config.cloud, cloud.options.contains(.insights) {
            mappers.append(CloudInsightsGraphMapper())
        }

        return mappers
    }
}
