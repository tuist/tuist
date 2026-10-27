import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistGenerator
import TuistHasher
import TuistLoader
import TuistLoggerTesting
import TuistLogging
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

#if canImport(TuistCacheEE)
    struct HashCacheCommandServiceTests {
        private let generatorFactory = MockCacheGeneratorFactorying()
        private let cacheGraphContentHasher = MockCacheGraphContentHashing()
        private let configLoader = MockConfigLoading()
        private let manifestloader = MockManifestLoading()
        private let subject: HashCacheCommandService!

        init() {
            subject = HashCacheCommandService(
                generatorFactory: generatorFactory,
                cacheGraphContentHasher: cacheGraphContentHasher,
                configLoader: configLoader,
                manifestLoader: manifestloader
            )
        }

        @Test func run_when_noRootManifest() async throws {
            // Given
            let path = try AbsolutePath(validating: "/project")
            given(manifestloader).hasRootManifest(at: .value(path)).willReturn(false)

            // When/Then
            await #expect(throws: HashCacheCommandServiceError.generatedProjectNotFound(path)) {
                try await subject.run(
                    path: path.pathString,
                    configuration: nil
                )
            }
        }

        @Test(.withMockedLogger()) func run_when_rootManifest() async throws {
            // Given
            let path = try AbsolutePath(validating: "/project")
            let config = Tuist.test()
            let generator = MockGenerating()
            let graph = Graph.test()
            let graphTarget = GraphTarget.test()
            let hash = UUID().uuidString
            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).binaryCacheWarmingPreload(
                config: .value(config),
                targetsToBinaryCache: .value([]),
                coverage: .value(.off)
            ).willReturn(generator)
            given(generator).load(path: .value(path), options: .value(config.project.generatedProject?.generationOptions))
                .willReturn(graph)
            given(manifestloader).hasRootManifest(at: .value(path)).willReturn(true)
            given(cacheGraphContentHasher).contentHashes(
                for: .value(graph),
                configuration: .value("Debug"),
                defaultConfiguration: .value(config.project.generatedProject?
                    .generationOptions.defaultConfiguration
                ),
                excludedTargets: .value([]),
                destination: .value(nil),
                coverage: .value(.off)
            ).willReturn([
                graphTarget: .test(hash: hash),
            ])
            // When
            try await subject.run(path: path.pathString, configuration: "Debug")

            // Then
            #expect(Logger.testingLogHandler.collected[.info, ==].contains(hash) == true)
        }

        @Test(
            .withMockedLogger(),
            .withMockedEnvironment(),
            arguments: [
                (variable: String?.none, option: true, expected: BinaryCacheCoverage.on),
                (variable: String?.none, option: false, expected: .off),
                (variable: "1", option: false, expected: .on),
                (variable: "0", option: true, expected: .off),
            ]
        )
        func run_hashesTheResolvedVariant(variable: String?, option: Bool, expected: BinaryCacheCoverage) async throws {
            Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
            Environment.mocked?.variables["TUIST_COVERAGE_ENABLED"] = variable
            let path = try AbsolutePath(validating: "/project")
            let config = Tuist.test(project: .generated(.test(generationOptions: .test(coverage: .init(enabled: option)))))
            let generator = MockGenerating()
            let graph = Graph.test()
            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).binaryCacheWarmingPreload(
                config: .value(config),
                targetsToBinaryCache: .value([]),
                coverage: .any
            )
            .willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(manifestloader).hasRootManifest(at: .value(path)).willReturn(true)
            given(cacheGraphContentHasher).contentHashes(
                for: .value(graph), configuration: .any, defaultConfiguration: .any, excludedTargets: .any, destination: .any,
                coverage: .any
            ).willReturn([:])

            try await subject.run(path: path.pathString, configuration: nil)

            verify(generatorFactory).binaryCacheWarmingPreload(
                config: .any, targetsToBinaryCache: .any, coverage: .value(expected)
            ).called(1)
            verify(cacheGraphContentHasher).contentHashes(
                for: .any, configuration: .any, defaultConfiguration: .any, excludedTargets: .any, destination: .any,
                coverage: .value(expected)
            ).called(1)
        }
    }
#endif
