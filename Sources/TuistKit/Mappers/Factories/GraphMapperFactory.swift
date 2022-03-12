import Foundation
import TSCBasic
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistGraph
import TuistSigning

/// The GraphMapperFactorying describes the interface of a factory of graph mappers.
/// Methods in the interface map with workflows exposed to the user.
protocol GraphMapperFactorying {
    ///  Returns the graph mapper that should be used for automation tasks such as build and test.
    /// - Returns: A graph mapper.
    func automation(config: Config, testsCacheDirectory: AbsolutePath) -> [GraphMapping]

    /// Returns the graph mapper for generating focused projects where some targets are pruned from the graph
    /// and others are replaced with their binary counterparts.
    /// - Returns: A graph mapper.
    func focus(
        config: Config,
        cache: Bool,
        cacheSources: Set<String>,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) -> [GraphMapping]

    /// Returns the graph mapper whose output project is a cacheable graph.
    /// - Returns: A graph mapper.
    func cache(includedTargets: Set<String>) -> [GraphMapping]

    /// Returns the default graph mapper that should be used from all the commands that require loading and processing the graph.
    /// - Returns: The default mapper.
    func `default`() -> [GraphMapping]
}

final class GraphMapperFactory: GraphMapperFactorying {
    fileprivate let contentHasher: ContentHashing

    init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    func automation(config: Config, testsCacheDirectory: AbsolutePath) -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(contentsOf: self.default())
        mappers.append(
            TestsCacheGraphMapper(hashesCacheDirectory: testsCacheDirectory, config: config)
        )
        mappers.append(TreeShakePrunedTargetsGraphMapper())
        return mappers
    }

    func focus(
        config: Config,
        cache: Bool,
        cacheSources: Set<String>,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(FocusTargetsGraphMappers(includedTargets: cacheSources))
        mappers.append(TreeShakePrunedTargetsGraphMapper())
        if cache {
            let focusTargetsGraphMapper = TargetsToCacheBinariesGraphMapper(
                config: config,
                cacheStorageProvider: CacheStorageProvider(config: config),
                sources: cacheSources,
                cacheProfile: cacheProfile,
                cacheOutputType: cacheOutputType
            )
            mappers.append(focusTargetsGraphMapper)
            mappers.append(TreeShakePrunedTargetsGraphMapper())
        }

        // The default mapper is executed at the end because it ensures that the workspace is in sync with the content in the graph.
        mappers.append(contentsOf: self.default())
        return mappers
    }

    func cache(includedTargets: Set<String>) -> [GraphMapping] {
        var mappers: [GraphMapping] = [
            FocusTargetsGraphMappers(includedTargets: includedTargets),
            TreeShakePrunedTargetsGraphMapper(),
        ]
        mappers += self.default()
        return mappers
    }

    func `default`() -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(UpdateWorkspaceProjectsGraphMapper())
        return mappers
    }
}
