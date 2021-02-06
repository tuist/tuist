import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGraph

final class AutomationGraphMapperProvider: GraphMapperProviding {
    private let testsCacheDirectory: AbsolutePath
    private let graphMapperProvider: GraphMapperProviding

    init(
        testsCacheDirectory: AbsolutePath,
        graphMapperProvider: GraphMapperProviding = GraphMapperProvider()
    ) {
        self.testsCacheDirectory = testsCacheDirectory
        self.graphMapperProvider = graphMapperProvider
    }

    func mapper(config: Config) -> GraphMapping {
        var mappers: [GraphMapping] = []
        mappers.append(graphMapperProvider.mapper(config: config))
        mappers.append(
            TestsCacheGraphMapper(testsCacheDirectory: testsCacheDirectory)
        )
        return SequentialGraphMapper(mappers)
    }
}
