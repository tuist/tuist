import Foundation
import Mockable
import TuistCore
import TuistGenerator
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

/// The protocol describes the interface of a factory that instantiates
/// generators for different commands
@Mockable
public protocol GeneratorFactorying {
    /// Returns the generator to generate a project to run tests on.
    /// - Parameter config: The project configuration
    /// - Parameter skipUITests: Whether UI tests should be skipped.
    /// - Parameter skipUnitTests: Whether Unit tests should be skipped.
    /// - Parameter ignoreBinaryCache: True to not include binaries from the cache.
    /// - Parameter ignoreSelectiveTesting: True to run all tests
    /// - Parameter cacheStorage: The cache storage instance.
    /// - Returns: A Generator instance.
    func testing(
        config: Tuist,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        skipUnitTests: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        ignoreSelectiveTesting: Bool,
        cacheStorage: CacheStoring,
        destination: SimulatorDeviceAndRuntime?
    ) -> Generating

    /// Returns the generator for focused projects.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The list of targets whose sources should be included.
    /// - Parameter configuration: The configuration to generate for.
    /// - Parameter cacheProfile: Cache profile to use for binary replacement.
    /// - Parameter cacheStorage: The cache storage instance.
    /// - Returns: The generator for focused projects.
    func generation(
        config: Tuist,
        includedTargets: Set<TargetQuery>,
        configuration: String?,
        cacheProfile: CacheProfile,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns a generator for building a project.
    /// - Parameters:
    ///     - config: The project configuration.
    ///     - configuration: The configuration to build for.
    ///     - ignoreBinaryCache: True to not include binaries from the cache.
    ///     - cacheStorage: The cache storage instance.
    /// - Returns: A Generator instance.
    func building(
        config: Tuist,
        configuration: String?,
        ignoreBinaryCache: Bool,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns the default generator.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The list of targets whose sources should be included.
    /// - Returns: A Generator instance.
    func defaultGenerator(
        config: Tuist,
        includedTargets: Set<TargetQuery>
    ) -> Generating
}

public class GeneratorFactory: GeneratorFactorying {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    public func testing(
        config: Tuist,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        skipUnitTests: Bool,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        ignoreSelectiveTesting _: Bool,
        cacheStorage _: CacheStoring,
        destination _: SimulatorDeviceAndRuntime?
    ) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.automation(
            skipUITests: skipUITests,
            skipUnitTests: skipUnitTests,
            tuist: config
        )
        let workspaceMapperFactory = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(mappers: projectMappers)
        )
        let graphMapperFactory = GraphMapperFactory()

        let graphMappers = graphMapperFactory.automation(
            config: config,
            testPlan: testPlan,
            includedTargets: Set(includedTargets.map(TargetQuery.init(stringLiteral:))),
            excludedTargets: Set(excludedTargets.map(TargetQuery.init(stringLiteral:)))
        )
        let workspaceMappers = workspaceMapperFactory.automation(
            tuist: config
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

    public func generation(
        config: Tuist,
        includedTargets: Set<TargetQuery>,
        configuration _: String?,
        cacheProfile _: CacheProfile,
        cacheStorage _: CacheStoring
    ) -> Generating {
        defaultGenerator(config: config, includedTargets: includedTargets)
    }

    public func building(
        config: Tuist,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        cacheStorage _: CacheStoring
    ) -> Generating {
        defaultGenerator(config: config, includedTargets: [])
    }

    public func defaultGenerator(
        config: Tuist,
        includedTargets: Set<TargetQuery>
    ) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.default(
            tuist: config
        )
        let workspaceMapperFactory = WorkspaceMapperFactory(
            projectMapper: SequentialProjectMapper(mappers: projectMappers)
        )
        let graphMapperFactory = GraphMapperFactory()
        let graphMappers = graphMapperFactory.automation(
            config: config,
            testPlan: nil,
            includedTargets: includedTargets,
            excludedTargets: []
        )
        let workspaceMappers = workspaceMapperFactory.default(
            tuist: config
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
}

#if canImport(TuistCacheEE)
    /// The protocol describes the interface of a factory that instantiates
    /// generators for different commands
    @Mockable
    protocol CacheGeneratorFactorying: GeneratorFactorying {
        /// Returns a generator that generates a cacheable project.
        /// - Parameter config: The project configuration.
        /// - Parameter targetsToBinaryCache: The targets to binary cache.
        /// - Parameter configuration: The configuration to generate for.
        /// - Parameter cacheStorage: The cache storage instance.
        /// - Returns: A Generator instance.
        func binaryCacheWarming(
            config: Tuist,
            targetsToBinaryCache: [Platform: Set<TargetQuery>],
            configuration: String,
            cacheStorage: CacheStoring
        ) -> Generating

        /// Returns a generator to load the graph before generating the project to warm the cache
        ///
        /// - Parameter config: The project configuration.
        /// - Parameter targetsToBinaryCache: The targets to binary cache.
        /// - Returns: A Generator instance.
        func binaryCacheWarmingPreload(
            config: Tuist,
            targetsToBinaryCache: Set<TargetQuery>
        ) -> Generating

        /// Returns the generator to generate a project to run tests on.
        /// - Parameter config: The project configuration
        /// - Parameter skipUITests: Whether UI tests should be skipped.
        /// - Parameter ignoreBinaryCache: True to not include binaries from the cache.
        /// - Parameter ignoreSelectiveTesting: True to run all tests
        /// - Parameter cacheStorage: The cache storage instance.
        /// - Returns: A Generator instance.
        func testing(
            config: Tuist,
            testPlan: String?,
            includedTargets: Set<String>,
            excludedTargets: Set<String>,
            skipUITests: Bool,
            skipUnitTests: Bool,
            configuration: String?,
            ignoreBinaryCache: Bool,
            ignoreSelectiveTesting: Bool,
            cacheStorage: CacheStoring,
            destination: SimulatorDeviceAndRuntime?
        ) -> Generating

        /// Returns the generator for focused projects.
        /// - Parameter config: The project configuration.
        /// - Parameter includedTargets: The list of targets whose sources should be included.
        /// - Parameter configuration: The configuration to generate for.
        /// - Parameter cacheProfile: Cache profile to use for binary replacement.
        /// - Parameter cacheStorage: The cache storage instance.
        /// - Returns: The generator for focused projects.
        func generation(
            config: Tuist,
            includedTargets: Set<TargetQuery>,
            configuration: String?,
            cacheProfile: CacheProfile,
            cacheStorage: CacheStoring
        ) -> Generating

        /// Returns a generator for building a project.
        /// - Parameters:
        ///     - config: The project configuration
        ///     - configuration: The configuration to build for.
        ///     - ignoreBinaryCache: True to not include binaries from the cache.
        ///     - cacheStorage: The cache storage instance.
        /// - Returns: A Generator instance
        func building(
            config: Tuist,
            configuration: String?,
            ignoreBinaryCache: Bool,
            cacheStorage: CacheStoring
        ) -> Generating

        /// Returns the default generator.
        /// - Parameter config: The project configuration.
        /// - Parameter includedTargets: The list of targets whose sources should be included.
        /// - Returns: A Generator instance.
        func defaultGenerator(
            config: Tuist,
            includedTargets: Set<TargetQuery>
        ) -> Generating
    }

    extension CacheGeneratorFactorying {
        /// Returns the default generator.
        /// - Parameter config: The project configuration.
        /// - Parameter sources: The list of targets whose sources should be included.
        /// - Returns: A Generator instance.
        func defaultGenerator(
            config: Tuist
        ) -> Generating {
            defaultGenerator(
                config: config,
                includedTargets: Set()
            )
        }
    }

    class CacheGeneratorFactory: CacheGeneratorFactorying {
        private let contentHasher: ContentHashing

        init(contentHasher: ContentHashing = ContentHasher()) {
            self.contentHasher = contentHasher
        }

        func generation(
            config: Tuist,
            includedTargets: Set<TargetQuery>,
            configuration: String?,
            cacheProfile: CacheProfile,
            cacheStorage: CacheStoring
        ) -> Generating {
            let contentHasher = ContentHasher()
            let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
            let projectMappers = projectMapperFactory.default(tuist: config)
            let workspaceMapperFactory = WorkspaceMapperFactory(
                projectMapper: SequentialProjectMapper(mappers: projectMappers)
            )
            let graphMapperFactory = CacheGraphMapperFactory(contentHasher: contentHasher)

            let graphMappers = graphMapperFactory.generation(
                config: config,
                cacheProfile: cacheProfile,
                cacheSources: includedTargets,
                configuration: configuration,
                cacheStorage: cacheStorage
            )
            let workspaceMappers = workspaceMapperFactory.default(tuist: config)
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

        func testing(
            config: Tuist,
            testPlan: String?,
            includedTargets: Set<String>,
            excludedTargets: Set<String>,
            skipUITests: Bool,
            skipUnitTests: Bool,
            configuration: String?,
            ignoreBinaryCache: Bool,
            ignoreSelectiveTesting: Bool,
            cacheStorage: CacheStoring,
            destination: SimulatorDeviceAndRuntime?
        ) -> Generating {
            let contentHasher = ContentHasher()
            let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
            let projectMappers = projectMapperFactory.automation(
                skipUITests: skipUITests,
                skipUnitTests: skipUnitTests,
                tuist: config
            )
            let workspaceMapperFactory = WorkspaceMapperFactory(
                projectMapper: SequentialProjectMapper(mappers: projectMappers)
            )
            let graphMapperFactory = CacheGraphMapperFactory(contentHasher: contentHasher)

            let graphMappers = graphMapperFactory.automation(
                config: config,
                ignoreBinaryCache: ignoreBinaryCache,
                ignoreSelectiveTesting: ignoreSelectiveTesting,
                testPlan: testPlan,
                includedTargets: Set(includedTargets.map(TargetQuery.init(stringLiteral:))),
                excludedTargets: Set(excludedTargets.map(TargetQuery.init(stringLiteral:))),
                configuration: configuration,
                cacheStorage: cacheStorage,
                destination: destination
            )
            let workspaceMappers = workspaceMapperFactory.automation(tuist: config)
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

        func building(
            config: Tuist,
            configuration: String?,
            ignoreBinaryCache: Bool,
            cacheStorage: CacheStoring
        ) -> Generating {
            let contentHasher = ContentHasher()
            let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
            let projectMappers = projectMapperFactory.automation(
                skipUITests: false, skipUnitTests: false, tuist: config
            )
            let workspaceMapperFactory = WorkspaceMapperFactory(
                projectMapper: SequentialProjectMapper(mappers: projectMappers)
            )
            let graphMapperFactory = CacheGraphMapperFactory(contentHasher: contentHasher)

            let graphMappers = graphMapperFactory.build(
                config: config,
                ignoreBinaryCache: ignoreBinaryCache,
                configuration: configuration,
                cacheStorage: cacheStorage
            )
            let workspaceMappers = workspaceMapperFactory.automation(tuist: config)
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

        func binaryCacheWarmingPreload(
            config: Tuist,
            targetsToBinaryCache: Set<TargetQuery>
        ) -> Generating {
            let contentHasher = ContentHasher()
            let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
            let projectMappers = projectMapperFactory.default(tuist: config)
            let workspaceMapperFactory =
                CacheWorkspaceMapperFactory(
                    projectMapper: SequentialProjectMapper(mappers: projectMappers)
                )
            let graphMapperFactory = CacheGraphMapperFactory(contentHasher: contentHasher)
            var graphMappers: [GraphMapping]
            graphMappers = graphMapperFactory.binaryCacheWarmingPreload(
                targetsToBinaryCache: targetsToBinaryCache,
                config: config
            )
            graphMappers = graphMappers.filter { !($0 is ExplicitDependencyGraphMapper) }
            let workspaceMappers = workspaceMapperFactory.binaryCacheWarmingPreload(tuist: config)
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

        func binaryCacheWarming(
            config: Tuist,
            targetsToBinaryCache: [XcodeGraph.Platform: Set<TargetQuery>],
            configuration: String,
            cacheStorage: CacheStoring
        ) -> Generating {
            let contentHasher = ContentHasher()
            let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
            let projectMappers = projectMapperFactory.default(tuist: config)
            let workspaceMapperFactory =
                CacheWorkspaceMapperFactory(
                    projectMapper: SequentialProjectMapper(mappers: projectMappers)
                )
            let graphMapperFactory = CacheGraphMapperFactory(contentHasher: contentHasher)

            var graphMappers: [GraphMapping] = graphMapperFactory.binaryCacheWarming(
                config: config,
                targets: targetsToBinaryCache,
                cacheSources: Set(targetsToBinaryCache.flatMap(\.value)),
                configuration: configuration,
                cacheStorage: cacheStorage
            )
            graphMappers = graphMappers.filter { !($0 is ExplicitDependencyGraphMapper) }

            let workspaceMappers = workspaceMapperFactory.binaryCacheWarming(tuist: config)
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

        func defaultGenerator(config: Tuist, includedTargets: Set<TargetQuery>) -> Generating {
            TuistKit.GeneratorFactory().defaultGenerator(
                config: config, includedTargets: includedTargets
            )
        }
    }

#endif
