import Foundation
import Mockable
import Path
import TuistAutomation
import TuistCore
import TuistGenerator
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

/// The protocol describes the interface of a factory that instantiates
/// generators for different commands
@Mockable
public protocol GeneratorFactorying {
    /// Returns the generator to generate a project to run tests on.
    /// - Parameter config: The project configuration
    /// - Parameter skipUITests: Whether UI tests should be skipped.
    /// - Parameter ignoreBinaryCache: True to not include binaries from the cache.
    /// - Parameter ignoreSelectiveTesting: True to run all tests
    /// - Parameter cacheStorage: The cache storage instance.
    /// - Returns: A Generator instance.
    func testing(
        config: Config,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        ignoreSelectiveTesting: Bool,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns the generator for focused projects.
    /// - Parameter config: The project configuration.
    /// - Parameter sources: The list of targets whose sources should be included.
    /// - Parameter configuration: The configuration to generate for.
    /// - Parameter ignoreBinaryCache: True to not include binaries from the cache.
    /// - Parameter cacheStorage: The cache storage instance.
    /// - Returns: The generator for focused projects.
    func generation(
        config: Config,
        sources: Set<String>,
        configuration: String?,
        ignoreBinaryCache: Bool,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns a generator for building a project.
    /// - Parameters:
    ///     - config: The project configuration
    /// - Returns: A Generator instance
    func building(
        config: Config,
        configuration: String?,
        ignoreBinaryCache: Bool,
        cacheStorage: CacheStoring
    ) -> Generating

    /// Returns the default generator.
    /// - Parameter config: The project configuration.
    /// - Returns: A Generator instance.
    func defaultGenerator(
        config: Config
    ) -> Generating
}

public class GeneratorFactory: GeneratorFactorying {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    public func testing(
        config: Config,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        ignoreSelectiveTesting _: Bool,
        cacheStorage _: CacheStoring
    ) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.automation(skipUITests: skipUITests)
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory()

        let graphMappers = graphMapperFactory.automation(
            config: config,
            testPlan: testPlan,
            includedTargets: includedTargets,
            excludedTargets: excludedTargets
        )
        let workspaceMappers = workspaceMapperFactory.automation()
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
        config: Config,
        sources _: Set<String>,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        cacheStorage _: CacheStoring
    ) -> Generating {
        defaultGenerator(config: config)
    }

    public func building(
        config: Config,
        configuration _: String?,
        ignoreBinaryCache _: Bool,
        cacheStorage _: CacheStoring
    ) -> Generating {
        defaultGenerator(config: config)
    }

    public func defaultGenerator(config: Config) -> Generating {
        let contentHasher = ContentHasher()
        let projectMapperFactory = ProjectMapperFactory(contentHasher: contentHasher)
        let projectMappers = projectMapperFactory.default()
        let workspaceMapperFactory = WorkspaceMapperFactory(projectMapper: SequentialProjectMapper(mappers: projectMappers))
        let graphMapperFactory = GraphMapperFactory()
        let graphMappers = graphMapperFactory.default(config: config)
        let workspaceMappers = workspaceMapperFactory.default()
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
