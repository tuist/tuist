import Foundation
import TuistCache
import TuistCore
import TuistGraph
import TSCBasic

final class PlayGraphMapperProvider: GraphMapperProviding {
    private let targetName: String
    private let temporaryDirectory: AbsolutePath
    private let focusGraphMapperProvider: FocusGraphMapperProvider

    init(targetName: String, temporaryDirectory: AbsolutePath, focusGraphMapperProvider: FocusGraphMapperProvider) {
        self.targetName = targetName
        self.temporaryDirectory = temporaryDirectory
        self.focusGraphMapperProvider = focusGraphMapperProvider
    }

    func mapper(config: Config) -> GraphMapping {
        let focusMapper = focusGraphMapperProvider.mapper(config: config)

        // Cache
        var mappers: [GraphMapping] = []
        mappers.append(PlayGraphMapper(targetName: targetName, temporaryDirectory: temporaryDirectory))
        mappers.append(focusMapper)

        return SequentialGraphMapper(mappers)
    }
}
