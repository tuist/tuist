import Foundation
import TuistGraph
import TuistCache
import TuistGenerator
import TuistLoader
import TSCBasic
import TuistSupport

/// The protocol describes the interface of a factory that instantiates
/// generators for different commands
protocol GeneratorFactorying {
    
    /// Returns the generator for focused projects.
    /// - Returns: The generator for focused projects.
    func focus(config: Config,
               sources: Set<String>,
               xcframeworks: Bool,
               cacheProfile: TuistGraph.Cache.Profile,
               ignoreCache: Bool) -> Generating
    
    /// Returns the generator to generate a project to run tests on.
    /// - Returns: A Generator instance.
    func test(
        config: Config,
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating
    
    /// Returns the default generator.
    /// - Returns: A Generator instance.
    func `default`() -> Generating
}

class GeneratorFactory: GeneratorFactorying {
    
    let graphMapperFactory: GraphMapperFactorying
    
    init(graphMapperFactory: GraphMapperFactorying = GraphMapperFactory()) {
        self.graphMapperFactory = graphMapperFactory
    }
    
    func focus(config: Config,
               sources: Set<String>,
               xcframeworks: Bool,
               cacheProfile: TuistGraph.Cache.Profile,
               ignoreCache: Bool) -> Generating {
        
        let contentHasher = CacheContentHasher()
        let graphMapper = graphMapperFactory.focus(config: config,
                                                   contentHasher: contentHasher,
                                                   cache: !ignoreCache,
                                                   cacheSources: sources,
                                                   cacheProfile: cacheProfile,
                                                   cacheOutputType: xcframeworks ? .xcframework : .framework)
        let projectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        return Generator(
            projectMapperProvider: projectMapperProvider,
            graphMapper: graphMapper,
            workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
    
    func `default`() -> Generating {
        let contentHasher = CacheContentHasher()
        let projectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        let graphMapper = graphMapperFactory.default()
        return Generator(
            projectMapperProvider: projectMapperProvider,
            graphMapper: graphMapper,
            workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
    
    func test(
        config: Config,
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating {
        let graphMapper = graphMapperFactory.automation(config: config, testsCacheDirectory: testsCacheDirectory)
        return Generator(
            projectMapperProvider: AutomationProjectMapperProvider(skipUITests: skipUITests),
            graphMapper: graphMapper,
            workspaceMapperProvider: AutomationWorkspaceMapperProvider(
                workspaceDirectory: FileHandler.shared.resolveSymlinks(automationPath),
                skipUITests: skipUITests
            ),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
    
}
