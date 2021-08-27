import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGraph

final class AutomationGraphMapperProvider: GraphMapperProviding {
    private let testsCacheDirectory: AbsolutePath
    private let graphMapperProvider: GraphMapperProviding
    private let skipTestsCache: Bool

    init(
        testsCacheDirectory: AbsolutePath,
        graphMapperProvider: GraphMapperProviding = GraphMapperProvider(),
        skipTestsCache: Bool
    ) {
        self.testsCacheDirectory = testsCacheDirectory
        self.graphMapperProvider = graphMapperProvider
        self.skipTestsCache = skipTestsCache
    }

    func mapper(config: Config) -> GraphMapping {
        var mappers: [GraphMapping] = []
        mappers.append(graphMapperProvider.mapper(config: config))

        if !skipTestsCache {
            mappers.append(
                TestsCacheGraphMapper(hashesCacheDirectory: testsCacheDirectory, config: config)
            )
            mappers.append(CacheTreeShakingGraphMapper())
        }
        return SequentialGraphMapper(mappers)
    }
}
