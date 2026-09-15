#if canImport(TuistCacheEE)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Path
    import Synchronization
    import Testing
    import TuistAutomation
    import TuistCache
    import TuistConfig
    import TuistConfigLoader
    import TuistCore
    import TuistHasher
    import TuistServer
    import TuistSupport
    import TuistXCActivityLog
    import TuistXcodeBuildProducts
    import XcodeGraph

    @testable import TuistCacheEE
    @testable import TuistKit
    @testable import TuistTesting

    struct CacheWarmCommandServiceTests {
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
        private let xcActivityLogController = MockXCActivityLogControlling()
        private let uploadBuildRunService = MockUploadBuildRunServicing()

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

        @Test(.inTemporaryDirectory) func run_reclaimsADestinationsBuildOutputBeforeBuildingTheNextOne() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let scratchDirectory = temporaryDirectory.appending(component: "cache-warm")
            let recorder = BuildRecorder()

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
                // Mockable hands this a synchronous closure even for an async requirement, so the seeding
                // and the observation both go through FileManager rather than FileSystem.
                .willProduce { _, _, _, _, derivedDataPath, _, arguments, passthroughXcodeBuildArguments in
                    let fileManager = FileManager.default
                    let derivedDataPath = try #require(derivedDataPath)
                    let productsDirectoryName = if arguments.contains(.destination("generic/platform=iOS Simulator")) {
                        "Debug-iphonesimulator"
                    } else if arguments.contains(.destination("generic/platform=iOS")) {
                        "Debug-iphoneos"
                    } else {
                        "Debug"
                    }

                    // macOS is built last, so what it sees is the peak the whole command has to fit on disk.
                    if productsDirectoryName == "Debug" {
                        recorder.recordIOSOutputAtLastBuild([
                            derivedDataPath.appending(components: ["Build", "Products", "Debug-iphonesimulator"]),
                            derivedDataPath.appending(components: ["Build", "Products", "Debug-iphoneos"]),
                            derivedDataPath.appending(components: [
                                "Build",
                                "Intermediates.noindex",
                                "Fixtures.build",
                                "Debug-iphonesimulator",
                            ]),
                        ].filter { fileManager.fileExists(atPath: $0.pathString) })
                    }

                    let index = try #require(passthroughXcodeBuildArguments.firstIndex(of: "-resultBundlePath"))
                    let resultBundlePath = try AbsolutePath(validating: passthroughXcodeBuildArguments[index + 1])
                    recorder.recordResultBundle(resultBundlePath)

                    for directory in [
                        resultBundlePath,
                        derivedDataPath.appending(components: ["Build", "Products", productsDirectoryName]),
                        derivedDataPath.appending(components: [
                            "Build",
                            "Intermediates.noindex",
                            "Fixtures.build",
                            productsDirectoryName,
                        ]),
                    ] {
                        try fileManager.createDirectory(atPath: directory.pathString, withIntermediateDirectories: true)
                        #expect(fileManager.createFile(
                            atPath: directory.appending(component: "Output").pathString,
                            contents: Data("output".utf8)
                        ))
                    }
                }

            try await run(
                noUpload: false,
                scratchDirectory: scratchDirectory,
                schemes: [.test(name: "Binaries-Cache-iOS"), .test(name: "Binaries-Cache-macOS")]
            )

            #expect(recorder.iOSOutputAtLastBuild == [])
            // The configuration's own directory holds host products every destination links against, so it is
            // the one the warm keeps.
            #expect(try await fileSystem.exists(
                scratchDirectory.appending(components: ["derived-data", "Build", "Products", "Debug"])
            ))
            #expect(recorder.resultBundlePaths.count == 3)
            for resultBundlePath in recorder.resultBundlePaths {
                #expect(try await fileSystem.exists(resultBundlePath) == false)
            }
        }

        @Test(.inTemporaryDirectory, arguments: [false, true], [false, true])
        func run_uploadsBuildLogBeforeCleanup_andPreservesBuildOutcome(buildFails: Bool, uploadFails: Bool) async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let config = Tuist.test(fullHandle: "tuist/fixture")
            let recorder = BuildRecorder()

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
                .willProduce { _, _, _, _, derivedDataPath, _, _, passthroughArguments in
                    let derivedDataPath = try #require(derivedDataPath)
                    let index = try #require(passthroughArguments.firstIndex(of: "-resultBundlePath"))
                    let resultBundlePath = try AbsolutePath(validating: passthroughArguments[index + 1])
                    recorder.recordResultBundle(resultBundlePath)
                    try FileManager.default.createDirectory(at: resultBundlePath.url, withIntermediateDirectories: true)
                    #expect(FileManager.default.createFile(
                        atPath: derivedDataPath.appending(component: "build.xcactivitylog").pathString,
                        contents: Data("build log".utf8)
                    ))
                    if buildFails { throw BuildFailure.compiler }
                }
            given(xcActivityLogController)
                .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
                .willProduce { derivedDataPath, filter in
                    let log = XCActivityLogFile.test(path: derivedDataPath.appending(component: "build.xcactivitylog"))
                    #expect(filter(log))
                    return log
                }
            given(uploadBuildRunService)
                .uploadBuildRun(
                    activityLogPath: .any,
                    projectPath: .value(temporaryDirectory),
                    config: .value(config),
                    scheme: .value("Bundles-Cache-iOS"),
                    configuration: .value("Release")
                )
                .willProduce { activityLogPath, _, _, _, _ in
                    #expect(FileManager.default.fileExists(atPath: activityLogPath.pathString))
                    let resultBundlePath = try #require(recorder.resultBundlePaths.first)
                    #expect(FileManager.default.fileExists(atPath: resultBundlePath.pathString))
                    if uploadFails { throw BuildFailure.upload }
                    return URL(string: "https://tuist.dev/tuist/fixture/builds/123")!
                }

            if buildFails {
                await #expect(throws: BuildFailure.compiler) {
                    try await run(
                        noUpload: false,
                        config: config,
                        configuration: "Release",
                        schemes: [.test(name: "Bundles-Cache-iOS")]
                    )
                }
            } else {
                try await run(
                    noUpload: false,
                    config: config,
                    configuration: "Release",
                    schemes: [.test(name: "Bundles-Cache-iOS")]
                )
            }

            verify(uploadBuildRunService)
                .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
                .called(1)
            for resultBundlePath in recorder.resultBundlePaths {
                #expect(try await fileSystem.exists(resultBundlePath) == false)
                #expect(try await fileSystem.exists(resultBundlePath.parentDirectory) == false)
            }
        }

        @Test(.inTemporaryDirectory, arguments: [false, true])
        func run_doesNotUploadMissingOrPreviousBuildLog(hasPreviousLog: Bool) async throws {
            stubBuild()
            given(xcActivityLogController)
                .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
                .willProduce { _, filter in
                    guard hasPreviousLog else { return nil }
                    let previousLog = XCActivityLogFile.test(timeStoppedRecording: .distantPast)
                    #expect(!filter(previousLog))
                    return filter(previousLog) ? previousLog : nil
                }

            try await run(
                noUpload: false,
                config: .test(fullHandle: "tuist/fixture"),
                schemes: [.test(name: "Bundles-Cache-iOS")]
            )

            verify(uploadBuildRunService)
                .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
                .called(0)
        }

        @Test(.inTemporaryDirectory, arguments: [false, true])
        func run_skipsBuildUploadsWithoutHandleOrWhenNoUpload(noUpload: Bool) async throws {
            stubBuild()
            try await run(
                noUpload: noUpload,
                config: .test(fullHandle: noUpload ? "tuist/fixture" : nil),
                schemes: [.test(name: "Bundles-Cache-iOS")]
            )

            verify(xcActivityLogController)
                .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
                .called(0)
            verify(uploadBuildRunService)
                .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
                .called(0)
        }

        @Test(.inTemporaryDirectory)
        func run_uploadsEachDestinationBuild() async throws {
            stubBuild()
            given(xcActivityLogController)
                .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
                .willProduce { _, _ in .test() }
            given(uploadBuildRunService)
                .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
                .willReturn(URL(string: "https://tuist.dev/tuist/fixture/builds/123")!)

            try await run(
                noUpload: false,
                config: .test(fullHandle: "tuist/fixture"),
                schemes: [.test(name: "Binaries-Cache-iOS"), .test(name: "Binaries-Cache-macOS")]
            )

            verify(uploadBuildRunService)
                .uploadBuildRun(
                    activityLogPath: .any,
                    projectPath: .any,
                    config: .any,
                    scheme: .value("Binaries-Cache-iOS"),
                    configuration: .value("Debug")
                )
                .called(2)
            verify(uploadBuildRunService)
                .uploadBuildRun(
                    activityLogPath: .any,
                    projectPath: .any,
                    config: .any,
                    scheme: .value("Binaries-Cache-macOS"),
                    configuration: .value("Debug")
                )
                .called(1)
        }

        private func stubBuild() {
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
        }

        private enum BuildFailure: Error, Equatable {
            case compiler
            case upload
        }

        private final class BuildRecorder: Sendable {
            private struct State {
                var iOSOutputAtLastBuild: [AbsolutePath]?
                var resultBundlePaths: [AbsolutePath] = []
            }

            private let state = Mutex(State())

            func recordIOSOutputAtLastBuild(_ paths: [AbsolutePath]) {
                state.withLock { $0.iOSOutputAtLastBuild = paths }
            }

            func recordResultBundle(_ path: AbsolutePath) {
                state.withLock { $0.resultBundlePaths.append(path) }
            }

            var iOSOutputAtLastBuild: [AbsolutePath]? { state.withLock { $0.iOSOutputAtLastBuild } }
            var resultBundlePaths: [AbsolutePath] { state.withLock { $0.resultBundlePaths } }
        }

        private func run(
            noUpload: Bool,
            config: Tuist = .test(),
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
                configLoader: configLoader,
                xcActivityLogController: xcActivityLogController,
                uploadBuildRunService: uploadBuildRunService
            )
        }
    }
#endif
