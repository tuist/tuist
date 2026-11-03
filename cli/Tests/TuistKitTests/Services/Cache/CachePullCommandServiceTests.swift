#if canImport(TuistCacheEE)
    import Foundation
    import Mockable
    import Path
    import Testing
    import TuistCache
    import TuistConfig
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistEnvironmentTesting
    import TuistHasher
    import TuistLoader
    import TuistServer
    import TuistTesting
    import XcodeGraph

    @testable import TuistCacheEE
    @testable import TuistKit

    struct CachePullCommandServiceTests {
        private let config = Tuist.test()
        private let cacheStorage = MockCacheStoring()
        private let cacheStorageFactory = MockCacheStorageFactorying()
        private let generatorFactory = MockCacheGeneratorFactorying()
        private let generator = MockGenerating()
        private let cacheGraphContentHasher = MockCacheGraphContentHashing()
        private let configLoader = MockConfigLoading()
        private let manifestLoader = MockManifestLoading()

        @Test(.withMockedEnvironment()) func run_pullsCacheableBinaries() async throws {
            let (path, graph, target, hash) = try configureGraph()
            let cacheItem = CacheItem.test(
                name: target.target.name,
                hash: hash,
                source: .remote,
                cacheCategory: .binaries
            )
            given(cacheStorage)
                .fetch(
                    .value(Set([CacheStorableItem(name: target.target.name, hash: hash)])),
                    cacheCategory: .value(.binaries)
                )
                .willReturn([cacheItem: path])

            try await subject.run(
                path: path.pathString,
                configuration: nil,
                targets: []
            )

            verify(cacheStorage)
                .fetch(
                    .value(Set([CacheStorableItem(name: target.target.name, hash: hash)])),
                    cacheCategory: .value(.binaries)
                )
                .called(1)
            verify(cacheStorageFactory)
                .cacheStorage(config: .value(config))
                .called(1)
            verify(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .value(nil),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    excludedTargets: .value([]),
                    destination: .value(nil)
                )
                .called(1)
        }

        @Test(.withMockedEnvironment()) func run_pullsSelectedTargetAndItsDependencies() async throws {
            let path = try AbsolutePath(validating: "/project")
            let dependency = Target.test(name: "Dependency", product: .framework)
            let target = Target.test(
                name: "Feature",
                product: .framework,
                dependencies: [.target(name: dependency.name)]
            )
            let project = Project.test(path: path, targets: [target, dependency])
            let graph = Graph.test(
                path: path,
                projects: [path: project],
                dependencies: [
                    .target(name: target.name, path: path): [.target(name: dependency.name, path: path)],
                ]
            )
            let featureTarget = GraphTarget(path: path, target: target, project: project)
            let dependencyTarget = GraphTarget(path: path, target: dependency, project: project)
            let featureHash = "feature-hash"
            let dependencyHash = "dependency-hash"
            configure(
                path: path,
                graph: graph,
                hashes: [
                    featureTarget: .test(hash: featureHash),
                    dependencyTarget: .test(hash: dependencyHash),
                ]
            )
            let items = Set([
                CacheStorableItem(name: target.name, hash: featureHash),
                CacheStorableItem(name: dependency.name, hash: dependencyHash),
            ])
            given(cacheStorage)
                .fetch(.value(items), cacheCategory: .value(.binaries))
                .willReturn([
                    .test(name: target.name, hash: featureHash, source: .remote, cacheCategory: .binaries): path,
                    .test(name: dependency.name, hash: dependencyHash, source: .local, cacheCategory: .binaries): path,
                ])

            try await subject.run(
                path: path.pathString,
                configuration: nil,
                targets: [target.name]
            )

            verify(cacheStorage)
                .fetch(.value(items), cacheCategory: .value(.binaries))
                .called(1)
        }

        @Test(.withMockedEnvironment()) func run_throwsWhenRequestedTargetsDoNotExist() async throws {
            let (path, graph, _, _) = try configureGraph()

            await #expect(throws: CachePullCommandServiceError.targetsNotFound(["Missing"])) {
                try await subject.run(
                    path: path.pathString,
                    configuration: nil,
                    targets: ["Missing"]
                )
            }

            verify(cacheStorage)
                .fetch(.any, cacheCategory: .any)
                .called(0)
            verify(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .value(nil),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    excludedTargets: .value([]),
                    destination: .value(nil)
                )
                .called(1)
        }

        @Test(.withMockedEnvironment()) func run_allowsMissingBinaries() async throws {
            let (path, _, _, _) = try configureGraph()
            given(cacheStorage)
                .fetch(.any, cacheCategory: .value(.binaries))
                .willReturn([:])

            try await subject.run(
                path: path.pathString,
                configuration: nil,
                targets: []
            )

            verify(cacheStorage)
                .fetch(.any, cacheCategory: .value(.binaries))
                .called(1)
        }

        private func configureGraph() throws -> (AbsolutePath, Graph, GraphTarget, String) {
            let path = try AbsolutePath(validating: "/project")
            let target = Target.test(name: "Feature", product: .framework)
            let project = Project.test(path: path, targets: [target])
            let graph = Graph.test(path: path, projects: [path: project])
            let graphTarget = GraphTarget(path: path, target: target, project: project)
            let hash = "feature-hash"
            configure(
                path: path,
                graph: graph,
                hashes: [graphTarget: .test(hash: hash)]
            )
            return (path, graph, graphTarget, hash)
        }

        private func configure(
            path: AbsolutePath,
            graph: Graph,
            hashes: [GraphTarget: TargetContentHash]
        ) {
            given(manifestLoader)
                .hasRootManifest(at: .value(path))
                .willReturn(true)
            given(configLoader)
                .loadConfig(path: .value(path))
                .willReturn(config)
            given(generatorFactory)
                .binaryCacheWarmingPreload(
                    config: .value(config),
                    targetsToBinaryCache: .value([])
                )
                .willReturn(generator)
            given(generator)
                .load(path: .value(path), options: .value(config.project.generatedProject?.generationOptions))
                .willReturn(graph)
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .value(nil),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    excludedTargets: .value([]),
                    destination: .value(nil)
                )
                .willReturn(hashes)
            given(cacheStorageFactory)
                .cacheStorage(config: .value(config))
                .willReturn(cacheStorage)
        }

        private var subject: CachePullCommandService {
            CachePullCommandService(
                generatorFactory: generatorFactory,
                cacheGraphContentHasher: cacheGraphContentHasher,
                cacheStorageFactory: cacheStorageFactory,
                configLoader: configLoader,
                manifestLoader: manifestLoader
            )
        }
    }
#endif
