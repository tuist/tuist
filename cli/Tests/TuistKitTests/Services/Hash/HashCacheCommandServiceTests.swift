import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
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
                targetsToBinaryCache: .value([])
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
                destination: .value(nil)
            ).willReturn([
                graphTarget: .test(hash: hash),
            ])
            // When
            try await subject.run(path: path.pathString, configuration: "Debug")

            // Then
            #expect(Logger.testingLogHandler.collected[.info, ==].contains(hash) == true)
        }
    }
#endif
