import Foundation
import Mockable
import TuistCache
import TuistConfig
import TuistCore
import TuistGenerator
import TuistHasher
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
        destination: SimulatorDeviceAndRuntime?,
        schemeName: String?,
        coverage: BinaryCacheCoverage
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
        cacheStorage: CacheStoring,
        coverage: BinaryCacheCoverage
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
        cacheStorage: CacheStoring,
        coverage: BinaryCacheCoverage
    ) -> Generating

    /// Returns the default generator.
    /// - Parameter config: The project configuration.
    /// - Parameter includedTargets: The list of targets whose sources should be included.
    /// - Returns: A Generator instance.
    func defaultGenerator(
        config: Tuist,
        includedTargets: Set<TargetQuery>,
        coverage: BinaryCacheCoverage
    ) -> Generating
}

public struct GeneratorFactory: GeneratorFactorying {
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
        destination _: SimulatorDeviceAndRuntime?,
        schemeName: String? = nil,
        coverage: BinaryCacheCoverage
    ) -> Generating {
        let config = config.resolvingCoverage(coverage)
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
            excludedTargets: Set(excludedTargets.map(TargetQuery.init(stringLiteral:))),
            includedProducts: [.unitTests, .uiTests],
            schemeName: schemeName
        )
        let workspaceMappers = workspaceMapperFactory.automation(
            tuist: config
        )
        return Generator(
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: ManifestLoader.current,
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
        cacheStorage _: CacheStoring,
        coverage: BinaryCacheCoverage
    ) -> Generating {
        defaultGenerator(config: config, includedTargets: includedTargets, coverage: coverage)
    }

    public func building(
        config: Tuist,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        cacheStorage _: CacheStoring,
        coverage: BinaryCacheCoverage
    ) -> Generating {
        defaultGenerator(config: config, includedTargets: [], coverage: coverage)
    }

    public func defaultGenerator(
        config: Tuist,
        includedTargets: Set<TargetQuery>,
        coverage: BinaryCacheCoverage
    ) -> Generating {
        let config = config.resolvingCoverage(coverage)
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
        return Generator(
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: ManifestLoader.current,
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
        /// - Parameter targetHashes: Content hashes the caller already computed for the same graph. Binary
        /// replacement reuses them instead of hashing the graph again; pass an empty map to have it hash.
        /// - Parameter coverage: The variant of the binary cache the warm fills: `.on` builds the
        /// repository-owned targets with coverage counters under the coverage key.
        /// Every factory method sets the config's `coverage.enabled` to the variant it's given, which the mappers
        /// and the binary-cache hashes read.
        /// - Returns: A Generator instance.
        func binaryCacheWarming(
            config: Tuist,
            targetsToBinaryCache: [Platform: Set<TargetQuery>],
            configuration: String,
            cacheStorage: CacheStoring,
            targetHashes: [TargetReference: TargetContentHash],
            coverage: BinaryCacheCoverage
        ) -> Generating

        /// Returns a generator to load the graph before generating the project to warm the cache
        ///
        /// - Parameter config: The project configuration.
        /// - Parameter targetsToBinaryCache: The targets to binary cache.
        /// - Returns: A Generator instance.
        func binaryCacheWarmingPreload(
            config: Tuist,
            targetsToBinaryCache: Set<TargetQuery>,
            coverage: BinaryCacheCoverage
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
            destination: SimulatorDeviceAndRuntime?,
            schemeName: String?,
            coverage: BinaryCacheCoverage
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
            cacheStorage: CacheStoring,
            coverage: BinaryCacheCoverage
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
            cacheStorage: CacheStoring,
            coverage: BinaryCacheCoverage
        ) -> Generating

        /// Returns the default generator.
        /// - Parameter config: The project configuration.
        /// - Parameter includedTargets: The list of targets whose sources should be included.
        /// - Returns: A Generator instance.
        func defaultGenerator(
            config: Tuist,
            includedTargets: Set<TargetQuery>,
            coverage: BinaryCacheCoverage
        ) -> Generating
    }

    extension CacheGeneratorFactorying {
        /// Returns the default generator.
        /// - Parameter config: The project configuration.
        /// - Parameter sources: The list of targets whose sources should be included.
        /// - Returns: A Generator instance.
        func defaultGenerator(
            config: Tuist,
            coverage: BinaryCacheCoverage
        ) -> Generating {
            defaultGenerator(
                config: config,
                includedTargets: Set(),
                coverage: coverage
            )
        }
    }

    struct CacheGeneratorFactory: CacheGeneratorFactorying {
        private let contentHasher: ContentHashing

        init(contentHasher: ContentHashing = ContentHasher()) {
            self.contentHasher = contentHasher
        }

        func generation(
            config: Tuist,
            includedTargets: Set<TargetQuery>,
            configuration: String?,
            cacheProfile: CacheProfile,
            cacheStorage: CacheStoring,
            coverage: BinaryCacheCoverage
        ) -> Generating {
            let config = config.resolvingCoverage(coverage)
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
            return Generator(
                manifestGraphLoader: ManifestGraphLoader(
                    manifestLoader: ManifestLoader.current,
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
            destination: SimulatorDeviceAndRuntime?,
            schemeName: String? = nil,
            coverage: BinaryCacheCoverage
        ) -> Generating {
            let config = config.resolvingCoverage(coverage)
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
                destination: destination,
                schemeName: schemeName
            )
            let workspaceMappers = workspaceMapperFactory.automation(tuist: config)
            return Generator(
                manifestGraphLoader: ManifestGraphLoader(
                    manifestLoader: ManifestLoader.current,
                    workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                    graphMapper: SequentialGraphMapper(graphMappers)
                )
            )
        }

        func building(
            config: Tuist,
            configuration: String?,
            ignoreBinaryCache: Bool,
            cacheStorage: CacheStoring,
            coverage: BinaryCacheCoverage
        ) -> Generating {
            let config = config.resolvingCoverage(coverage)
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
            return Generator(
                manifestGraphLoader: ManifestGraphLoader(
                    manifestLoader: ManifestLoader.current,
                    workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                    graphMapper: SequentialGraphMapper(graphMappers)
                )
            )
        }

        func binaryCacheWarmingPreload(
            config: Tuist,
            targetsToBinaryCache: Set<TargetQuery>,
            coverage: BinaryCacheCoverage
        ) -> Generating {
            let config = config.resolvingCoverage(coverage)
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
            return Generator(
                manifestGraphLoader: ManifestGraphLoader(
                    manifestLoader: ManifestLoader.current,
                    workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                    graphMapper: SequentialGraphMapper(graphMappers)
                )
            )
        }

        func binaryCacheWarming(
            config: Tuist,
            targetsToBinaryCache: [XcodeGraph.Platform: Set<TargetQuery>],
            configuration: String,
            cacheStorage: CacheStoring,
            targetHashes: [TargetReference: TargetContentHash],
            coverage: BinaryCacheCoverage
        ) -> Generating {
            let config = config.resolvingCoverage(coverage)
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
                cacheStorage: cacheStorage,
                targetHashes: targetHashes
            )
            graphMappers = graphMappers.filter { !($0 is ExplicitDependencyGraphMapper) }

            let workspaceMappers = workspaceMapperFactory.binaryCacheWarming(
                tuist: config
            )
            return Generator(
                manifestGraphLoader: ManifestGraphLoader(
                    manifestLoader: ManifestLoader.current,
                    workspaceMapper: SequentialWorkspaceMapper(mappers: workspaceMappers),
                    graphMapper: SequentialGraphMapper(graphMappers)
                )
            )
        }

        func defaultGenerator(config: Tuist, includedTargets: Set<TargetQuery>, coverage: BinaryCacheCoverage) -> Generating {
            TuistKit.GeneratorFactory().defaultGenerator(
                config: config, includedTargets: includedTargets, coverage: coverage
            )
        }
    }

#endif
