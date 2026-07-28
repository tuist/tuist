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
    import TuistSupport
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

        @Test(.inTemporaryDirectory) func run_passesRequestedConfigurationToContentHasher() async throws {
            try await run(noUpload: false, configuration: "Release")
        }

        @Test(.inTemporaryDirectory) func run_usesAndPreservesCallerOwnedScratchDirectory() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let scratchDirectory = temporaryDirectory.appending(component: "cache-warm")

            try await run(noUpload: false, scratchDirectory: scratchDirectory)

            #expect(try await fileSystem.exists(scratchDirectory, isDirectory: true))
            #expect(try await fileSystem.exists(scratchDirectory.appending(component: "derived-data"), isDirectory: true))
            #expect(try await fileSystem.exists(scratchDirectory.appending(component: "Metadatas"), isDirectory: true))
        }

        @Test(.inTemporaryDirectory) func run_rejectsNonEmptyCallerOwnedScratchDirectoryBeforeLoadingConfig() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let scratchDirectory = temporaryDirectory.appending(component: "cache-warm")
            let existingFile = scratchDirectory.appending(component: "existing")
            try await fileSystem.makeDirectory(at: scratchDirectory)
            try await fileSystem.touch(existingFile)

            await #expect(throws: CacheWarmScratchDirectoryError.notEmpty(scratchDirectory)) {
                try await run(noUpload: false, scratchDirectory: scratchDirectory)
            }
            #expect(try await fileSystem.exists(existingFile))
            verify(configLoader)
                .loadConfig(path: .any)
                .called(0)
        }

        @Test(.inTemporaryDirectory) func run_rejectsCallerOwnedScratchDirectoryForForeignBuildTargets() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let scratchDirectory = temporaryDirectory.appending(component: "cache-warm")
            let foreignBuild = ForeignBuild(
                script: "build",
                inputs: [],
                output: .xcframework(
                    path: temporaryDirectory.appending(component: "Fixtures.xcframework"),
                    linking: .dynamic
                )
            )

            await #expect(throws: CacheWarmForeignBuildOutputValidatorError.unsupported(
                scratchDirectory: scratchDirectory,
                targetNames: ["Fixtures"]
            )) {
                try await run(
                    noUpload: false,
                    scratchDirectory: scratchDirectory,
                    foreignBuild: foreignBuild
                )
            }
            verify(generatorFactory)
                .binaryCacheWarming(
                    config: .any,
                    targetsToBinaryCache: .any,
                    configuration: .any,
                    cacheStorage: .any
                )
                .called(0)
        }

        @Test(.inTemporaryDirectory) func run_placesCompilationCacheInCallerOwnedScratchDirectory() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let scratchDirectory = temporaryDirectory.appending(component: "cache-warm")
            let compilationCachePath = scratchDirectory.appending(component: "CompilationCache.noindex")

            given(xcodeBuildController)
                .build(
                    .any,
                    scheme: .any,
                    destination: .any,
                    rosetta: .any,
                    derivedDataPath: .any,
                    clean: .any,
                    arguments: .any,
                    passthroughXcodeBuildArguments: .any
                )
                .willReturn()

            try await run(
                noUpload: false,
                scratchDirectory: scratchDirectory,
                schemes: [.test(name: "Bundles-Cache-iOS")]
            )

            verify(xcodeBuildController)
                .build(
                    .any,
                    scheme: .value("Bundles-Cache-iOS"),
                    destination: .any,
                    rosetta: .any,
                    derivedDataPath: .any,
                    clean: .any,
                    arguments: .matching {
                        $0.contains(.xcarg("COMPILATION_CACHE_CAS_PATH", compilationCachePath.pathString))
                    },
                    passthroughXcodeBuildArguments: .any
                )
                .called(1)
        }

        private func run(
            noUpload: Bool,
            configuration: String? = nil,
            scratchDirectory: AbsolutePath? = nil,
            schemes: [Scheme] = [],
            foreignBuild: ForeignBuild? = nil
        ) async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let resolvedConfiguration = configuration ?? "Debug"
            let target = Target.test(name: "Fixtures", product: .bundle, foreignBuild: foreignBuild)
            let project = Project.test(path: temporaryDirectory, targets: [target], schemes: [])
            let graphTarget = GraphTarget(path: temporaryDirectory, target: target, project: project)
            let graph = Graph.test(
                path: temporaryDirectory,
                workspace: .test(path: temporaryDirectory, schemes: schemes),
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
                    configuration: .value(configuration),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    graph: .value(graph)
                )
                .willReturn(resolvedConfiguration)
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .value(configuration),
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
                    configuration: .value(resolvedConfiguration),
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
                configuration: configuration,
                targetsToBinaryCache: [],
                externalOnly: false,
                generateOnly: false,
                noUpload: noUpload,
                cacheProfile: nil,
                scratchDirectory: scratchDirectory?.pathString
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
