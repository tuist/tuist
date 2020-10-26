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
    init() {}

    func mapper(config: Config) -> GraphMapping {
        SequentialGraphMapper(mappers(config: config))
    }

    func mappers(config _: Config) -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        return mappers
    }
}
