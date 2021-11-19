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

    /// Returns the generator for play projects.
    /// - Parameter config: The project configuration.
    /// - Parameter sources: The list of targets whose sources should be inclued.
    /// - Parameter xcframeworks: Whether targets should be cached as xcframeworks.
    /// - Parameter cacheProfile: The caching profile.
    /// - Parameter ignoreCache: True to not include binaries from the cache.
    /// - Parameter temporaryDirectory: The path to the temporary directory.
    /// - Returns: The generator for focused projects.
    func play(
        config: Config,
        sources: Set<String>,
        xcframeworks: Bool,
        cacheProfile: TuistGraph.Cache.Profile,
        ignoreCache: Bool,
        temporaryDirectory: AbsolutePath
    ) -> Generating

    /// Returns the default generator.
    /// - Parameter config: The project configuration.
    /// - Returns: A Generator instance.
    func `default`(config: Config) -> Generating

    /// Returns a generator that generates a cacheable project.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The targets to cache. When nil, it caches all the cacheable targets.
    /// - Returns: A Generator instance.
    func cache(config: Config, includedTargets: Set<String>?) -> Generating
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
        return Generator(
            projectMapper: SequentialProjectMapper(mappers: projectMappers),
            graphMapper: SequentialGraphMapper(graphMappers),
            workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
            manifestLoaderFactory: ManifestLoaderFactory()
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
        return Generator(
            projectMapper: SequentialProjectMapper(mappers: projectMappers),
            graphMapper: SequentialGraphMapper(graphMappers),
            workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }

    func cache(config: Config, includedTargets: Set<String>?) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.cache(config: config)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory(contentHasher: contentHasher)
        let graphMappers = graphMapperFactory.cache(includedTargets: includedTargets)
        let workspaceMappers = workspaceMapperFactory.cache(config: config, includedTargets: includedTargets ?? [])
        return Generator(
            projectMapper: SequentialProjectMapper(mappers: projectMappers),
            graphMapper: SequentialGraphMapper(graphMappers),
            workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }

    func play(
        config: Config,
        sources: Set<String>,
        xcframeworks: Bool,
        cacheProfile: TuistGraph.Cache.Profile,
        ignoreCache: Bool,
        temporaryDirectory: AbsolutePath
    ) -> Generating {
        let contentHasher = CacheContentHasher()
        // TODO: Add support for multiple targets
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.default(config: config)
        let graphMapperFactory = GraphMapperFactory(contentHasher: contentHasher)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))

        let graphMappers = graphMapperFactory.play(
            config: config,
            cache: !ignoreCache,
            cacheSources: sources,
            cacheProfile: cacheProfile,
            cacheOutputType: xcframeworks ? .xcframework : .framework,
            targetName: sources.first!,
            temporaryDirectory: temporaryDirectory
        )
        let workspaceMappers = workspaceMapperFactory.default(config: config)
        return Generator(
            projectMapper: SequentialProjectMapper(mappers: projectMappers),
            graphMapper: SequentialGraphMapper(graphMappers),
            workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
            manifestLoaderFactory: ManifestLoaderFactory()
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
        return Generator(
            projectMapper: SequentialProjectMapper(mappers: projectMappers),
            graphMapper: SequentialGraphMapper(graphMappers),
            workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}
