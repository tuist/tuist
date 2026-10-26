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
    import TuistEnvironment
    import TuistGit
    import TuistHasher
    import TuistProcess
    import TuistRootDirectoryLocator
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
        private let gitController = MockGitControlling()
        private let rootDirectoryLocator = MockRootDirectoryLocating()
        private let fileSystem = FileSystem()
        private let commandRunner = MockCommandRunning()

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

        @Test(.inTemporaryDirectory) func run_handsTheHashesItComputedToTheWarmProjectGenerator() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let fingerprints = ["ios-device": "device-hash", "ios-simulator": "simulator-hash"]
            var targetHash = TargetContentHash.test(hash: "fixtures-hash")
            targetHash.binaryCacheFingerprints = fingerprints

            try await run(noUpload: false, fingerprints: fingerprints)

            verify(generatorFactory)
                .binaryCacheWarming(
                    config: .any,
                    targetsToBinaryCache: .any,
                    configuration: .any,
                    cacheStorage: .any,
                    targetHashes: .value([
                        TargetReference(projectPath: temporaryDirectory, name: "Fixtures"): targetHash,
                    ]),
                    coverage: .any
                )
                .called(1)
            verify(cacheStorage)
                .fetch(
                    .matching { items in
                        items.count == 1 && items.first?.metadata.binaryCacheFingerprints == fingerprints
                    },
                    cacheCategory: .value(.binaries)
                )
                .called(1)
        }

        /// Hashing a target runs its `additionalHashingInputs` scripts, and excluding one also makes its
        /// dependents unhashable, which is what stops a warm from storing artifacts the same profile could
        /// never read back. So a narrowing profile keeps its exclusions on the hashing call, and the
        /// resulting map is too narrow to hand to binary replacement, which runs under `.allPossible`.
        @Test(.inTemporaryDirectory) func run_keepsProfileExclusions_andHandsOverNoHashes() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let externalProjectPath = temporaryDirectory.appending(component: "external")
            let localTarget = Target.test(name: "Local", product: .framework)
            let externalTarget = Target.test(name: "External", product: .framework)
            let localProject = Project.test(path: temporaryDirectory, targets: [localTarget])
            let externalProject = Project.test(
                path: externalProjectPath,
                targets: [externalTarget],
                type: .external(hash: nil)
            )
            let externalGraphTarget = GraphTarget(
                path: externalProjectPath,
                target: externalTarget,
                project: externalProject
            )
            let graph = Graph.test(
                path: temporaryDirectory,
                workspace: .test(path: temporaryDirectory),
                projects: [temporaryDirectory: localProject, externalProjectPath: externalProject]
            )

            given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(config)
            given(cacheStorageFactory).cacheStorage(config: .value(config)).willReturn(cacheStorage)
            given(cacheStorageFactory).cacheLocalStorage().willReturn(localCacheStorage)
            given(generatorFactory)
                .binaryCacheWarmingPreload(config: .value(config), targetsToBinaryCache: .value([]), coverage: .any)
                .willReturn(preloadGenerator)
            given(preloadGenerator)
                .load(path: .value(temporaryDirectory), options: .value(config.project.generatedProject?.generationOptions))
                .willReturn(graph)
            given(defaultConfigurationFetcher)
                .fetch(configuration: .any, defaultConfiguration: .any, graph: .value(graph))
                .willReturn("Debug")
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .any,
                    defaultConfiguration: .any,
                    excludedTargets: .value(["Local"]),
                    destination: .value(nil),
                    coverage: .value(.off)
                )
                .willReturn([externalGraphTarget: .test(hash: "external-hash")])
            given(cacheStorage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([:])
            given(cacheStorage).republishIfNeeded(.any, cacheCategory: .value(.binaries)).willReturn()
            given(generatorFactory)
                .binaryCacheWarming(
                    config: .any,
                    targetsToBinaryCache: .any,
                    configuration: .any,
                    cacheStorage: .any,
                    targetHashes: .any,
                    coverage: .any
                )
                .willReturn(generator)
            given(generator)
                .generateWithGraph(path: .value(temporaryDirectory), options: .any)
                .willReturn((temporaryDirectory, graph, MapperEnvironment()))
            given(cacheStorage).store(.any, cacheCategory: .value(.binaries)).willReturn([])

            try await subject.run(
                path: temporaryDirectory.pathString,
                configuration: nil,
                targetsToBinaryCache: [],
                externalOnly: true,
                generateOnly: true,
                noUpload: false,
                cacheProfile: nil,
                scratchDirectory: nil
            )

            verify(generatorFactory)
                .binaryCacheWarming(
                    config: .any,
                    targetsToBinaryCache: .matching { targets in
                        Set(targets.values.flatMap { $0 }) == [TargetQuery(stringLiteral: "External")]
                    },
                    configuration: .any,
                    cacheStorage: .any,
                    targetHashes: .value([:]),
                    coverage: .any
                )
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

        @Test(.inTemporaryDirectory) func run_republishesLocalHits_whenUploading() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(components: "Binaries", "Fixtures.bundle")
            let fingerprints = ["ios-simulator": "simulator-hash"]

            try await run(
                noUpload: false,
                fingerprints: fingerprints,
                fetched: [CacheItem(name: "Fixtures", hash: "fixtures-hash", source: .local, cacheCategory: .binaries): path]
            )

            verify(cacheStorage)
                .republishIfNeeded(
                    .matching { items in
                        items.count == 1 && items.first?.key.hash == "fixtures-hash"
                            && items.first?.key.metadata.binaryCacheFingerprints == fingerprints && items.first?.value == path
                    },
                    cacheCategory: .value(.binaries)
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory) func run_storesMissesBeforeRepublishingLocalHits() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(components: "Binaries", "Cached.bundle")
            let failure = CacheUploadFailure(
                item: CacheStorableItem(name: "Cached", hash: "cached-hash"),
                reason: "request timed out"
            )

            let error = await #expect(throws: CacheWarmCommandServiceError.self) {
                try await run(
                    noUpload: false,
                    fetched: [CacheItem(name: "Cached", hash: "cached-hash", source: .local, cacheCategory: .binaries): path],
                    cachedTarget: true,
                    republishError: CacheUploadError(failures: [failure])
                )
            }

            #expect(error?.errorDescription?.contains("  - Cached (cached-hash): request timed out") == true)
            verify(cacheStorage)
                .store(.any, cacheCategory: .value(.binaries))
                .called(1)
            verify(cacheStorage)
                .republishIfNeeded(
                    .matching { $0.keys.map(\.name) == ["Cached"] },
                    cacheCategory: .value(.binaries)
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory) func run_doesNotRepublishLocalHits_whenNoUpload() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(components: "Binaries", "Fixtures.bundle")

            try await run(
                noUpload: true,
                fetched: [CacheItem(name: "Fixtures", hash: "fixtures-hash", source: .local, cacheCategory: .binaries): path]
            )

            verify(cacheStorage)
                .republishIfNeeded(.any, cacheCategory: .any)
                .called(0)
        }

        @Test(.inTemporaryDirectory) func run_doesNotRepublishLocalHits_whenGenerateOnly() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(components: "Binaries", "Fixtures.bundle")

            try await run(
                noUpload: false,
                fetched: [CacheItem(name: "Fixtures", hash: "fixtures-hash", source: .local, cacheCategory: .binaries): path],
                generateOnly: true
            )

            verify(cacheStorage)
                .republishIfNeeded(.any, cacheCategory: .any)
                .called(0)
        }

        @Test(.inTemporaryDirectory) func run_fails_listing_the_targets_that_failed_to_upload() async throws {
            let failure = CacheUploadFailure(
                item: CacheStorableItem(name: "Fixtures", hash: "fixtures-hash"),
                reason: "request timed out"
            )

            let error = await #expect(throws: CacheWarmCommandServiceError.self) {
                try await run(noUpload: false, storeError: CacheUploadError(failures: [failure]))
            }

            #expect(error?.errorDescription?.contains("  - Fixtures (fixtures-hash): request timed out") == true)
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
                    cacheStorage: .any,
                    targetHashes: .any,
                    coverage: .any
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

        @Test(
            .inTemporaryDirectory,
            .withMockedEnvironment()
        ) func run_buildsRepositoryTargetsWithCoverage_whenTheEnvironmentTurnsCoverageOn() async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            stubFrameworkBuilds()
            stubXCFrameworkCreation()

            try await run(
                noUpload: true,
                schemes: [.test(name: "Binaries-Cache-iOS")],
                targetProduct: .framework,
                projectSettings: .test(defaultSettings: .recommended),
                coverageVariable: "1"
            )

            verify(cacheGraphContentHasher)
                .contentHashes(
                    for: .any, configuration: .any, defaultConfiguration: .any, excludedTargets: .any, destination: .any,
                    coverage: .value(.on)
                )
                .called(1)
            verify(generatorFactory)
                .binaryCacheWarming(
                    config: .any, targetsToBinaryCache: .any, configuration: .any, cacheStorage: .any, targetHashes: .any,
                    coverage: .value(.on)
                )
                .called(1)
            verify(xcodeBuildController)
                .build(
                    .any,
                    scheme: .any,
                    destination: .any,
                    rosetta: .any,
                    derivedDataPath: .any,
                    clean: .any,
                    arguments: .any,
                    passthroughXcodeBuildArguments: .matching { arguments in
                        arguments
                            .contains(
                                "CLANG_COVERAGE_MAPPING=$(TUIST_BINARY_CACHE_COVERAGE_MAPPING_$(TUIST_BINARY_CACHE_COVERAGE))"
                            )
                            && arguments.contains { $0.hasPrefix("TUIST_BINARY_CACHE_COVERAGE_SWIFT_FLAGS_YES=")
                                && $0.contains("-coverage-prefix-map \"\(temporaryDirectory.pathString)=/TUIST_SOURCE_ROOT\"")
                            }
                    }
                )
                .called(2)
        }

        @Test(.inTemporaryDirectory) func run_buildsPlainBinaries_whenWarmingWithoutCoverage() async throws {
            stubFrameworkBuilds()
            stubXCFrameworkCreation()

            try await run(
                noUpload: true,
                schemes: [.test(name: "Binaries-Cache-iOS")],
                targetProduct: .framework,
                projectSettings: .test(defaultSettings: .recommended)
            )

            verify(xcodeBuildController)
                .build(
                    .any,
                    scheme: .any,
                    destination: .any,
                    rosetta: .any,
                    derivedDataPath: .any,
                    clean: .any,
                    arguments: .any,
                    passthroughXcodeBuildArguments: .matching { arguments in
                        !arguments.contains { $0.hasPrefix("CLANG_COVERAGE_MAPPING=") }
                    }
                )
                .called(2)
        }

        @Test(.inTemporaryDirectory, .withMockedEnvironment())
        func run_buildsRepositoryTargetsWithCoverage_whenTheConfigTurnsCoverageOn() async throws {
            stubFrameworkBuilds()
            stubXCFrameworkCreation()

            try await run(
                noUpload: true,
                schemes: [.test(name: "Binaries-Cache-iOS")],
                targetProduct: .framework,
                projectSettings: .test(defaultSettings: .recommended),
                coverageOption: true
            )

            verify(generatorFactory)
                .binaryCacheWarmingPreload(config: .any, targetsToBinaryCache: .any, coverage: .value(.on))
                .called(1)
            verify(cacheGraphContentHasher)
                .contentHashes(
                    for: .any, configuration: .any, defaultConfiguration: .any, excludedTargets: .any, destination: .any,
                    coverage: .value(.on)
                )
                .called(1)
            verify(generatorFactory)
                .binaryCacheWarming(
                    config: .any, targetsToBinaryCache: .any, configuration: .any, cacheStorage: .any, targetHashes: .any,
                    coverage: .value(.on)
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory, .withMockedEnvironment())
        func run_warmsPlainBinaries_whenTheConfigTurnsCoverageOnForAReleaseConfiguration() async throws {
            stubFrameworkBuilds()
            stubXCFrameworkCreation()

            try await run(
                noUpload: true,
                configuration: "Release",
                schemes: [.test(name: "Binaries-Cache-iOS")],
                targetProduct: .framework,
                projectSettings: .test(defaultSettings: .recommended),
                coverageOption: true
            )

            verify(cacheGraphContentHasher)
                .contentHashes(
                    for: .any, configuration: .any, defaultConfiguration: .any, excludedTargets: .any, destination: .any,
                    coverage: .value(.off)
                )
                .called(1)
            verify(generatorFactory)
                .binaryCacheWarming(
                    config: .any, targetsToBinaryCache: .any, configuration: .any, cacheStorage: .any, targetHashes: .any,
                    coverage: .value(.off)
                )
                .called(1)
            verify(xcodeBuildController)
                .build(
                    .any, scheme: .any, destination: .any, rosetta: .any, derivedDataPath: .any, clean: .any,
                    arguments: .any,
                    passthroughXcodeBuildArguments: .matching { arguments in
                        !arguments.contains { $0.hasPrefix("CLANG_COVERAGE_MAPPING=") }
                    }
                )
                .called(2)
        }

        @Test(.inTemporaryDirectory) func run_bundlesDSYMsIntoXCFrameworks_whenWarmingAReleaseConfiguration() async throws {
            stubFrameworkBuilds()
            stubXCFrameworkCreation()

            try await run(
                noUpload: true,
                configuration: "Release",
                schemes: [.test(name: "Binaries-Cache-iOS")],
                targetProduct: .framework,
                projectSettings: .test(defaultSettings: .recommended)
            )

            verify(xcodeBuildController)
                .build(
                    .any,
                    scheme: .any,
                    destination: .any,
                    rosetta: .any,
                    derivedDataPath: .any,
                    clean: .any,
                    arguments: .matching { $0.contains(.xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym")) },
                    passthroughXcodeBuildArguments: .any
                )
                .called(2)
            verify(xcodeBuildController)
                .createXCFramework(
                    arguments: .matching { arguments in
                        let slices = Self.xcframeworkSlices(arguments)
                        return slices.count == 2 && slices.allSatisfy { $0.debugSymbols == "\($0.framework).dSYM" }
                    },
                    output: .any
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory) func run_bundlesDSYMsIntoXCFrameworks_whenWarmingADebugConfiguration() async throws {
            stubFrameworkBuilds()
            stubXCFrameworkCreation()

            try await run(
                noUpload: true,
                schemes: [.test(name: "Binaries-Cache-iOS")],
                targetProduct: .framework,
                projectSettings: .test(defaultSettings: .recommended)
            )

            verify(xcodeBuildController)
                .build(
                    .any,
                    scheme: .any,
                    destination: .any,
                    rosetta: .any,
                    derivedDataPath: .any,
                    clean: .any,
                    arguments: .matching { $0.contains(.xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym")) },
                    passthroughXcodeBuildArguments: .any
                )
                .called(2)
            verify(xcodeBuildController)
                .createXCFramework(
                    arguments: .matching { arguments in
                        let slices = Self.xcframeworkSlices(arguments)
                        return slices.count == 2 && slices.allSatisfy { $0.debugSymbols == "\($0.framework).dSYM" }
                    },
                    output: .any
                )
                .called(1)
        }

        @Test(.inTemporaryDirectory)
        func metadataUsesTheCustomXcodeProjectNameAndIsolatesUnsupportedTargets() async throws {
            let root = try #require(FileSystem.temporaryTestDirectory)
            let unsupported = try await debuggingInput(at: root.appending(component: "Unsupported"))
            let healthy = try await debuggingInput(at: root.appending(component: "Healthy"))
            given(commandRunner).run(arguments: .any, environment: .any, workingDirectory: .any).willProduce { arguments, _, _ in
                AsyncThrowingStream { continuation in
                    if arguments.last?.contains("Healthy") == true {
                        continuation.yield(.standardOutput(Array("/^root/Sources/Feature.swift\n".utf8)))
                    }
                    continuation.finish()
                }
            }
            #expect(try await !subject.writeDebuggingMetadata(
                unsupported.metadata, target: unsupported.target, artifact: unsupported.artifact,
                productsDirectories: [unsupported.products]
            ))
            #expect(try await subject.writeDebuggingMetadata(
                healthy.metadata, target: healthy.target, artifact: healthy.artifact,
                productsDirectories: [healthy.products]
            ))
            let relative = "Sources/Feature.swift"
            let path = healthy.artifact.appending(components: "macos-arm64", CachedModuleDebuggingMetadata.fileName)
            let recorded = try JSONDecoder().decode(CachedModuleDebuggingMetadata.self, from: await fileSystem.readFile(at: path))
            #expect(recorded.debugPaths[relative] == ["/^root/Sources/Feature.swift"])
            #expect(try await !fileSystem.exists(unsupported.artifact.appending(
                components: "macos-arm64", CachedModuleDebuggingMetadata.fileName
            )))
        }

        @Test(.inTemporaryDirectory, arguments: ["prefix-map", "info-plist", "empty-slices"])
        func malformedDebuggingInputsSkipPublicationRatherThanAbortTheWarm(kind: String) async throws {
            let root = try #require(FileSystem.temporaryTestDirectory)
            let fixture = try await debuggingInput(at: root)
            if kind == "prefix-map" {
                let map = fixture.products.appending(
                    components: "tuist-prefix-maps", "CustomProject.build", "Feature.build.json"
                )
                try await fileSystem.writeText("[]", at: map)
            } else if kind == "info-plist" {
                try await fileSystem.writeText("invalid property list", at: fixture.artifact.appending(component: "Info.plist"))
            } else {
                let info: [String: Any] = [
                    "AvailableLibraries": [[String: String]](), "CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0",
                ]
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                    .write(to: fixture.artifact.appending(component: "Info.plist").url)
            }
            #expect(try await !subject.writeDebuggingMetadata(
                fixture.metadata, target: fixture.target, artifact: fixture.artifact, productsDirectories: [fixture.products]
            ))
        }

        @Test(.inTemporaryDirectory)
        func scriptGeneratedPlaceholdersSkipOnlyTheirTargetWithoutClaimingMutation() async throws {
            let root = try #require(FileSystem.temporaryTestDirectory)
            let fixture = try await debuggingInput(at: root)
            let output = root.appending(component: "Generated.swift")
            var source = SourceFile(path: output, contentHash: try ContentHasher().hash("generated-file-Generated.swift"))
            source.contentHashIsPlaceholder = true
            var target = fixture.target.target
            target.sources.append(source)
            let graphTarget = GraphTarget(path: root, target: target, project: fixture.target.project)
            let before = try await CachedModuleDebuggingMetadata.capture(target: graphTarget)
            try await fileSystem.writeText("arbitrary script output", at: output)
            #expect(try await !subject.writeDebuggingMetadata(
                before, target: graphTarget, artifact: fixture.artifact, productsDirectories: [fixture.products]
            ))
            given(commandRunner).run(arguments: .any, environment: .any, workingDirectory: .any).willProduce { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.standardOutput(Array("/^root/Sources/Feature.swift\n".utf8)))
                    continuation.finish()
                }
            }
            #expect(try await subject.writeDebuggingMetadata(
                fixture.metadata, target: fixture.target, artifact: fixture.artifact, productsDirectories: [fixture.products]
            ))
            let declared = try #require(fixture.target.target.sources.first?.path)
            try await fileSystem.writeText("mutated declared source", at: declared)
            do {
                _ = try await subject.writeDebuggingMetadata(
                    before, target: graphTarget, artifact: fixture.artifact, productsDirectories: [fixture.products]
                )
                Issue.record("An unsupported generated output must not hide mutation of a declared source")
            } catch let CacheWarmCommandServiceError.sourcesChangedDuringBuild(target) {
                #expect(target == "Feature")
            }
        }

        @Test(.inTemporaryDirectory)
        func metadataPublicationPropagatesSourceMutationAndCancellation() async throws {
            let root = try #require(FileSystem.temporaryTestDirectory)
            let fixture = try await debuggingInput(at: root)
            given(commandRunner).run(arguments: .any, environment: .any, workingDirectory: .any).willProduce { _, _, _ in
                AsyncThrowingStream { $0.finish(throwing: CancellationError()) }
            }
            await #expect(throws: CancellationError.self) {
                try await subject.writeDebuggingMetadata(
                    fixture.metadata, target: fixture.target, artifact: fixture.artifact, productsDirectories: [fixture.products]
                )
            }
            try await fileSystem.writeText("mutated", at: #require(fixture.target.target.sources.first?.path))
            do {
                _ = try await subject.writeDebuggingMetadata(
                    fixture.metadata, target: fixture.target, artifact: fixture.artifact, productsDirectories: [fixture.products]
                )
                Issue.record("Source mutation must abort publication")
            } catch let CacheWarmCommandServiceError.sourcesChangedDuringBuild(target) {
                #expect(target == "Feature")
            }
        }

        private func debuggingInput(at root: AbsolutePath) async throws -> (
            target: GraphTarget, metadata: CachedModuleDebuggingMetadata, artifact: AbsolutePath, products: AbsolutePath
        ) {
            let source = root.appending(components: "Sources", "Feature.swift")
            try await fileSystem.makeDirectory(at: source.parentDirectory)
            try await fileSystem.writeText("public let value = 42", at: source)
            let target = Target.test(name: "Feature", product: .framework, sources: [SourceFile(path: source)])
            let project = Project.test(
                path: root, sourceRootPath: root, xcodeProjPath: root.appending(component: "CustomProject.xcodeproj"),
                name: "DisplayName", targets: [target]
            )
            let graphTarget = GraphTarget(path: root, target: target, project: project)
            let artifact = root.appending(component: "Feature.xcframework")
            try await fileSystem.makeDirectory(at: artifact.appending(component: "macos-arm64"))
            let library: [String: Any] = [
                "LibraryIdentifier": "macos-arm64", "LibraryPath": "Feature.framework",
                "SupportedPlatform": "macos", "SupportedArchitectures": ["arm64"],
            ]
            let info: [String: Any] = [
                "AvailableLibraries": [library], "CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0",
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: artifact.appending(component: "Info.plist").url)
            let products = root.appending(component: "products")
            let prefixMap = products.appending(components: "tuist-prefix-maps", "CustomProject.build", "Feature.build.json")
            try await fileSystem.makeDirectory(at: prefixMap.parentDirectory)
            try await fileSystem.writeAsJSON(["/^root": root.pathString], at: prefixMap)
            return (graphTarget, try await CachedModuleDebuggingMetadata.capture(target: graphTarget), artifact, products)
        }

        private func stubXCFrameworkCreation() {
            given(xcodeBuildController).createXCFramework(arguments: .any, output: .any).willProduce { arguments, output in
                let libraries: [[String: Any]] = try Self.xcframeworkSlices(arguments).map { slice in
                    let simulator = slice.framework.contains("iphonesimulator")
                    let identifier = simulator ? "ios-arm64-simulator" : "ios-arm64"
                    try FileManager.default.createDirectory(
                        at: output.appending(component: identifier).url,
                        withIntermediateDirectories: true
                    )
                    var library: [String: Any] = [
                        "LibraryIdentifier": identifier, "LibraryPath": "Fixtures.framework",
                        "SupportedPlatform": "ios", "SupportedArchitectures": ["arm64"],
                    ]
                    if simulator { library["SupportedPlatformVariant"] = "simulator" }
                    return library
                }
                let info: [String: Any] = [
                    "AvailableLibraries": libraries,
                    "CFBundlePackageType": "XFWK",
                    "XCFrameworkFormatVersion": "1.0",
                ]
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                    .write(to: output.appending(component: "Info.plist").url)
            }
        }

        /// Stubs builds to lay out a `Fixtures.framework` in the products directory, plus its dSYM when the build asks
        /// for one, as Xcode does.
        private func stubFrameworkBuilds() {
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
                .willProduce { _, _, _, _, derivedDataPath, _, arguments, _ in
                    let fileManager = FileManager.default
                    let derivedDataPath = try #require(derivedDataPath)
                    let configuration = try #require(arguments.lazy.compactMap { argument -> String? in
                        if case let .configuration(configuration) = argument { return configuration }
                        return nil
                    }.first)
                    let sdk = arguments.contains(.destination("generic/platform=iOS Simulator")) ? "iphonesimulator" : "iphoneos"
                    let productsDirectory = derivedDataPath.appending(components: [
                        "Build", "Products", "\(configuration)-\(sdk)",
                    ])
                    var products = ["Fixtures.framework"]
                    if arguments.contains(.xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym")) {
                        products.append("Fixtures.framework.dSYM")
                    }
                    for product in products {
                        try fileManager.createDirectory(
                            atPath: productsDirectory.appending(component: product).pathString,
                            withIntermediateDirectories: true
                        )
                    }
                }
        }

        private static func xcframeworkSlices(_ arguments: [String]) -> [(framework: String, debugSymbols: String?)] {
            var slices: [(framework: String, debugSymbols: String?)] = []
            var index = arguments.startIndex
            while index < arguments.endIndex - 1 {
                switch arguments[index] {
                case "-framework":
                    slices.append((framework: arguments[index + 1], debugSymbols: nil))
                case "-debug-symbols":
                    guard !slices.isEmpty else { return [] }
                    slices[slices.count - 1].debugSymbols = arguments[index + 1]
                default:
                    break
                }
                index += 2
            }
            return slices
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
            configuration: String? = nil,
            scratchDirectory: AbsolutePath? = nil,
            schemes: [Scheme] = [],
            foreignBuild: ForeignBuild? = nil,
            storeError: Error? = nil,
            fingerprints: [String: String] = [:],
            targetProduct: Product = .bundle,
            projectSettings: Settings = .test(),
            fetched: [CacheItem: AbsolutePath] = [:],
            generateOnly: Bool = false,
            cachedTarget: Bool = false,
            republishError: Error? = nil,
            coverageVariable: String? = nil,
            coverageOption: Bool = false
        ) async throws {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let config = coverageOption
                ? Tuist.test(project: .generated(.test(generationOptions: .test(coverage: .init(enabled: true)))))
                : config
            if coverageVariable != nil || coverageOption {
                Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
                Environment.mocked?.variables["TUIST_COVERAGE_ENABLED"] = coverageVariable
                given(gitController).isInGitRepository(workingDirectory: .any).willReturn(false)
                given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)
            }
            let resolvedConfiguration = configuration ?? "Debug"
            let target = Target.test(name: "Fixtures", product: targetProduct, foreignBuild: foreignBuild)
            let cached = Target.test(name: "Cached", product: .bundle)
            let project = Project.test(
                path: temporaryDirectory,
                settings: projectSettings,
                targets: cachedTarget ? [target, cached] : [target],
                schemes: []
            )
            let graphTarget = GraphTarget(path: temporaryDirectory, target: target, project: project)
            var hashes: [GraphTarget: TargetContentHash] = [:]
            if cachedTarget {
                hashes[GraphTarget(path: temporaryDirectory, target: cached, project: project)] = .test(hash: "cached-hash")
            }
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
                    targetsToBinaryCache: .value([]),
                    coverage: .any
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
            var targetHash = TargetContentHash.test(hash: "fixtures-hash")
            targetHash.binaryCacheFingerprints = fingerprints
            hashes[graphTarget] = targetHash
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .value(graph),
                    configuration: .value(configuration),
                    defaultConfiguration: .value(config.project.generatedProject?.generationOptions.defaultConfiguration),
                    excludedTargets: .value([]),
                    destination: .value(nil),
                    coverage: .any
                )
                .willReturn(hashes)
            given(cacheStorage)
                .fetch(.any, cacheCategory: .value(.binaries))
                .willReturn(fetched)
            if let republishError {
                given(cacheStorage)
                    .republishIfNeeded(.any, cacheCategory: .value(.binaries))
                    .willThrow(republishError)
            } else {
                given(cacheStorage)
                    .republishIfNeeded(.any, cacheCategory: .value(.binaries))
                    .willReturn()
            }
            given(generatorFactory)
                .binaryCacheWarming(
                    config: .value(config),
                    targetsToBinaryCache: .any,
                    configuration: .value(resolvedConfiguration),
                    cacheStorage: .any,
                    targetHashes: .any,
                    coverage: .any
                )
                .willReturn(generator)
            given(generator)
                .generateWithGraph(
                    path: .value(temporaryDirectory),
                    options: .value(config.project.generatedProject?.generationOptions)
                )
                .willReturn((temporaryDirectory, graph, MapperEnvironment()))
            if let storeError {
                given(cacheStorage)
                    .store(.any, cacheCategory: .value(.binaries))
                    .willThrow(storeError)
            } else {
                given(cacheStorage)
                    .store(.any, cacheCategory: .value(.binaries))
                    .willReturn([])
            }
            given(localCacheStorage)
                .store(.any, cacheCategory: .value(.binaries))
                .willReturn([])

            try await subject.run(
                path: temporaryDirectory.pathString,
                configuration: configuration,
                targetsToBinaryCache: [],
                externalOnly: false,
                generateOnly: generateOnly,
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
                commandRunner: commandRunner,
                coverageBuildSourcesService: CoverageBuildSourcesService(
                    gitController: gitController,
                    rootDirectoryLocator: rootDirectoryLocator
                )
            )
        }
    }
#endif
