import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistSupport

/// The protocol describes the interface of a factory that instantiates
/// generators for different commands
protocol GeneratorFactorying {
    /// Returns the generator for focused projects.
    /// - Parameter config: The project configuration.
    /// - Parameter sources: The list of targets whose sources should be inclued.
    /// - Parameter xcframeworks: Whether targets should be cached as xcframeworks.
    /// - Parameter cacheProfile: The caching profile.
    /// - Parameter ignoreCache: True to not include binaries from the cache.
    /// - Returns: The generator for focused projects.
    func focus(config: Config,
               sources: Set<String>,
               xcframeworks: Bool,
               cacheProfile: TuistGraph.Cache.Profile,
               ignoreCache: Bool) -> Generating

    /// Returns the generator to generate a project to run tests on.
    /// - Parameter config: The project configuration
    /// - Parameter automationPath: The automation path.
    /// - Parameter testsCacheDirectory: The cache directory used for tests.
    /// - Parameter skipUITests: Whether UI tests should be skipped.
    /// - Returns: A Generator instance.
    func test(
        config: Config,
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating

    /// Returns the default generator.
    /// - Parameter config: The project configuration.
    /// - Returns: A Generator instance.
    func `default`(config: Config) -> Generating

    /// Returns a generator that generates a cacheable project.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The targets to cache. When nil, it caches all the cacheable targets.
    /// - Parameter xcframeworks: Whether targets should be cached as xcframeworks.
    /// - Parameter cacheProfile: The caching profile.
    /// - Returns: A Generator instance.
    func cache(
        config: Config,
        includedTargets: Set<String>,
        focusedTargets: Set<String>?,
        xcframeworks: Bool,
        cacheProfile: TuistGraph.Cache.Profile
    ) -> Generating
}

class GeneratorFactory: GeneratorFactorying {
    private let contentHasher: ContentHashing

    init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    func focus(config: Config,
               sources: Set<String>,
               xcframeworks: Bool,
               cacheProfile: TuistGraph.Cache.Profile,
               ignoreCache: Bool) -> Generating
    {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.default(config: config)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory(contentHasher: contentHasher)

        let graphMappers = graphMapperFactory.focus(
            config: config,
            cache: !ignoreCache,
            cacheSources: sources,
            cacheProfile: cacheProfile,
            cacheOutputType: xcframeworks ? .xcframework : .framework
        )
        let workspaceMappers = workspaceMapperFactory.default(config: config)
        let manifestLoader = ManifestLoaderFactory().createManifestLoader()
        return Generator(
            manifestLoader: manifestLoader,
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                graphMapper: SequentialGraphMapper(graphMappers)
            )
        )
    }

    func `default`(config: Config) -> Generating {
        self.default(config: config, contentHasher: ContentHasher())
    }

    func test(
        config: Config,
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.automation(config: config, skipUITests: skipUITests)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory(contentHasher: contentHasher)

        let graphMappers = graphMapperFactory.automation(config: config, testsCacheDirectory: testsCacheDirectory)
        let workspaceMappers = workspaceMapperFactory.automation(
            config: config,
            workspaceDirectory: FileHandler.shared.resolveSymlinks(automationPath)
        )
        let manifestLoader = ManifestLoaderFactory().createManifestLoader()
        return Generator(
            manifestLoader: manifestLoader,
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                graphMapper: SequentialGraphMapper(graphMappers)
            )
        )
    }

    func cache(
        config: Config,
        includedTargets: Set<String>,
        focusedTargets: Set<String>?,
        xcframeworks: Bool,
        cacheProfile: TuistGraph.Cache.Profile
    ) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.default(config: config)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory(contentHasher: contentHasher)

        let graphMappers: [GraphMapping]
        if let focusedTargets = focusedTargets {
            graphMappers = graphMapperFactory.focus(
                config: config,
                cache: true,
                cacheSources: focusedTargets,
                cacheProfile: cacheProfile,
                cacheOutputType: xcframeworks ? .xcframework : .framework
            ) + graphMapperFactory.cache(includedTargets: includedTargets)
        } else {
            graphMappers = graphMapperFactory.cache(includedTargets: includedTargets)
        }

        let workspaceMappers = workspaceMapperFactory.cache(config: config, includedTargets: includedTargets)
        let manifestLoader = ManifestLoaderFactory().createManifestLoader()
        return Generator(
            manifestLoader: manifestLoader,
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                graphMapper: SequentialGraphMapper(graphMappers)
            )
        )
    }

    // MARK: - Fileprivate

    func `default`(config: Config, contentHasher _: ContentHashing) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.default(config: config)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory(contentHasher: contentHasher)
        let graphMappers = graphMapperFactory.default()
        let workspaceMappers = workspaceMapperFactory.default(config: config)
        let manifestLoader = ManifestLoaderFactory().createManifestLoader()
        return Generator(
            manifestLoader: manifestLoader,
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                graphMapper: SequentialGraphMapper(graphMappers)
            )
        )
    }
}
