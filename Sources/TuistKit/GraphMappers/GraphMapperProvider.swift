import Foundation
import TSCBasic
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistGraph
import TuistSigning

/// It defines an interface for providing the mappers to be used for a specific configuration.
protocol GraphMapperProviding {
    /// Returns a list of mappers to be used for a specific configuration.
    /// - Parameter config: Project's configuration.
    func mapper(config: Config) -> GraphMapping
}

final class GraphMapperProvider: GraphMapperProviding {
    let mappers: (Config) -> [GraphMapping]
    
    init(mappers: @escaping (Config) -> [GraphMapping]) {
        self.mappers = mappers
    }
    
    func mapper(config: Config) -> GraphMapping {
        return SequentialGraphMapper(mappers(config))
    }
}
