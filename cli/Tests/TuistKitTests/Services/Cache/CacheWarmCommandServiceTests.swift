#if canImport(TuistCacheEE)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Path
    import Testing
    import TuistAutomation
    import TuistCache
    import TuistConfig
    import TuistConfigLoader
    import TuistCore
    import TuistHasher
    import TuistServer
    import TuistXcodeBuildProducts
    import XcodeGraph

    @testable import TuistCacheEE
    @testable import TuistKit
    @testable import TuistTesting

    struct CacheWarmCommandServiceTests {
        private let config = Tuist.test()
        private let cacheStorage = MockCacheStoring()
        private let localCacheStorage = MockCacheStoring()
        private let cacheStorageFactory = MockCacheStorageFactorying()
        private let generatorFactory = MockCacheGeneratorFactorying()
        private let preloadGenerator = MockGenerating()
        private let generator = MockGenerating()
        private let defaultConfigurationFetcher = MockDefaultConfigurationFetching()
        private let xcodeBuildController = MockXcodeBuildControlling()
        private let simulatorController = MockSimulatorControlling()
        private let xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocating()
        private let contentHasher = MockContentHashing()
        private let cacheGraphContentHasher = MockCacheGraphContentHashing()
        private let configLoader = MockConfigLoading()
        private let fileSystem = FileSystem()

        @Test(.inTemporaryDirectory) func run_usesLocalCacheStorage_whenNoUpload() async throws {
            try await run(noUpload: true)

            verify(localCacheStorage)
                .store(.any, cacheCategory: .value(.binaries))
                .called(1)
            verify(cacheStorage)
                .store(.any, cacheCategory: .any)
                .called(0)
            verify(cacheStorageFactory)
                .cacheLocalStorage()
                .called(1)
        }

        @Test(.inTemporaryDirectory) func run_usesConfiguredCacheStorage_whenUploading() async throws {
            try await run(noUpload: false)

            verify(cacheStorage)
                .store(.any, cacheCategory: .value(.binaries))
                .called(1)
            verify(localCacheStorage)
                .store(.any, cacheCategory: .any)
                .called(0)
            verify(cacheStorageFactory)
                .cacheLocalStorage()
                .called(0)
        }

        private func run(noUpload: Bool) async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let target = Target.test(name: "Fixtures", product: .bundle)
            let project = Project.test(path: temporaryDirectory, targets: [target], schemes: [])
            let graphTarget = GraphTarget(path: temporaryDirectory, target: target, project: project)
            let graph = Graph.test(
                path: temporaryDirectory,
                projects: [temporaryDirectory: project]
            )

            given(configLoader)
                .loadConfig(path: .value(temporaryDirectory))
                .willReturn(config)
            given(cacheStorageFactory)
                .cacheStorage(config: .value(config))
                .willReturn(cacheStorage)
            given(cacheStorageFactory)
                .cacheLocalStorage()
                .willReturn(localCacheStorage)
            given(generatorFactory)
                .binaryCacheWarmingPreload(
                    config: .value(config),
                    targetsToBinaryCache: .value([])
                )
                .willReturn(preloadGenerator)
            given(preloadGenerator)
                .load(path: .value(temporaryDirectory), options: .value(config.project.generatedProject?.generationOptions))
                .willReturn(graph)
            given(defaultConfigurationFetcher)
                .fetch(
                    configuration: .value(nil),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    graph: .value(graph)
                )
                .willReturn("Debug")
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .value("Debug"),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    excludedTargets: .value([]),
                    destination: .value(nil)
                )
                .willReturn([graphTarget: .test(hash: "fixtures-hash")])
            given(cacheStorage)
                .fetch(.any, cacheCategory: .value(.binaries))
                .willReturn([:])
            given(generatorFactory)
                .binaryCacheWarming(
                    config: .value(config),
                    targetsToBinaryCache: .any,
                    configuration: .value("Debug"),
                    cacheStorage: .any
                )
                .willReturn(generator)
            given(generator)
                .generateWithGraph(
                    path: .value(temporaryDirectory),
                    options: .value(config.project.generatedProject?.generationOptions)
                )
                .willReturn((temporaryDirectory, graph, MapperEnvironment()))
            given(cacheStorage)
                .store(.any, cacheCategory: .value(.binaries))
                .willReturn([])
            given(localCacheStorage)
                .store(.any, cacheCategory: .value(.binaries))
                .willReturn([])

            try await subject.run(
                path: temporaryDirectory.pathString,
                configuration: nil,
                targetsToBinaryCache: [],
                externalOnly: false,
                generateOnly: false,
                noUpload: noUpload,
                cacheProfile: nil
            )
        }

        private var subject: CacheWarmCommandService {
            CacheWarmCommandService(
                generatorFactory: generatorFactory,
                cacheWarmGraphLinter: CacheWarmGraphLinter(),
                defaultConfigurationFetcher: defaultConfigurationFetcher,
                xcodeBuildController: xcodeBuildController,
                simulatorController: simulatorController,
                xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
                fileSystem: fileSystem,
                contentHasher: contentHasher,
                cacheGraphContentHasher: cacheGraphContentHasher,
                cacheStorageFactory: cacheStorageFactory,
                configLoader: configLoader
            )
        }
    }
#endif
