import Foundation
import TSCBasic
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistGraph

final class GraphMapperProviderFactory {
    
    func automationProvider(testsCacheDirectory: AbsolutePath) -> GraphMapperProviding {
        return GraphMapperProvider { config in
            var mappers: [GraphMapping] = []
            mappers.append(contentsOf: self.defaultMappers())
            mappers.append(
                TestsCacheGraphMapper(hashesCacheDirectory: testsCacheDirectory, config: config)
            )
            mappers.append(CacheTreeShakingGraphMapper())
            return mappers
        }
    }
    
    func focusProvider(contentHasher: ContentHashing,
                       cache: Bool,
                       cacheSources: Set<String>,
                       cacheProfile: TuistGraph.Cache.Profile,
                       cacheOutputType: CacheOutputType) -> GraphMapperProviding {
        return GraphMapperProvider { config in
            var mappers: [GraphMapping] = []
            mappers.append(FilterTargetsDependenciesTreeGraphMapper(includedTargets: cacheSources))
            mappers.append(CacheTreeShakingGraphMapper())
            if cache {
                let cacheMapper = CacheMapper(
                    config: config,
                    cacheStorageProvider: CacheStorageProvider(config: config),
                    sources: cacheSources,
                    cacheProfile: cacheProfile,
                    cacheOutputType: cacheOutputType
                )
                mappers.append(cacheMapper)
                mappers.append(CacheTreeShakingGraphMapper())
            }

            // The default mapper is executed at the end because it ensures that the workspace is in sync with the content in the graph.
            mappers.append(contentsOf: self.defaultMappers())
            return mappers
        }
    }
    
    func cacheProvider(includedTargets: Set<String>?) -> GraphMapperProviding {
        return GraphMapperProvider { config in
            var mappers: [GraphMapping] = [
                FilterTargetsDependenciesTreeGraphMapper(includedTargets: includedTargets),
                CacheTreeShakingGraphMapper()
            ]
            mappers += self.defaultMappers()
            return mappers
        }
    }
    
    func defaultProvider() -> GraphMapperProviding {
        return GraphMapperProvider { config in
            self.defaultMappers()
        }
    }
    
    // MARK: - Private
    
    private func defaultMappers() -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(UpdateWorkspaceProjectsGraphMapper())
        return mappers
    }
}
