import Foundation
import Mockable
import Path
import SnapshotTesting
import Testing
import TuistCache
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistGenerator
import TuistHasher
import TuistLoader
import TuistNooraTesting
import TuistServer
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct HashSelectiveTestingCommandServiceTests {
    private var subject: HashSelectiveTestingCommandService!
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var cacheStorage: MockCacheStoring!
    private var configLoader: MockConfigLoading!

    init() {
        generatorFactory = MockGeneratorFactorying()
        generator = .init()
        cacheStorageFactory = MockCacheStorageFactorying()
        cacheStorage = MockCacheStoring()
        given(cacheStorageFactory)
            .cacheLocalStorage()
            .willReturn(cacheStorage)
        given(generatorFactory).testing(
            config: .any,
            testPlan: .any,
            includedTargets: .any,
            excludedTargets: .any,
            skipUITests: .any,
            skipUnitTests: .any,
            configuration: .any,
            ignoreBinaryCache: .any,
            ignoreSelectiveTesting: .any,
            cacheStorage: .any,
            destination: .any,
            schemeName: .any
        ).willReturn(generator)

        configLoader = .init()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        subject = HashSelectiveTestingCommandService(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            configLoader: configLoader
        )
    }

    @Test func run_outputsTheHashes_fromMapperEnvironment() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let projectPath = try AbsolutePath(validating: "/project/Module")
            let config = Tuist.test()
            let graph = Graph.test()
            var environment = MapperEnvironment()
            environment.targetTestHashes = [
                projectPath: [
                    "AlphaTests": "alpha-hash",
                    "BetaTests": "beta-hash",
                ],
            ]

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generator).loadWithEnvironment(path: .value(path), options: .any).willReturn((graph, environment))

            // When
            try await subject.run(path: path.pathString)

            // Then
            try TuistTest.expectLogs("AlphaTests - alpha-hash")
            try TuistTest.expectLogs("BetaTests - beta-hash")
        }
    }

    @Test func run_usesTheTestingGenerator_notTheDefaultOne() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let projectPath = try AbsolutePath(validating: "/project/Module")
            let config = Tuist.test()
            let graph = Graph.test()
            var environment = MapperEnvironment()
            environment.targetTestHashes = [projectPath: ["SomeTests": "hash"]]

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generator).loadWithEnvironment(path: .value(path), options: .any).willReturn((graph, environment))

            // When
            try await subject.run(path: path.pathString)

            // Then: the testing generator (which uses CacheEE's TestsCacheGraphMapper for hashing,
            // matching what `tuist test` does at cache-fetch time) must be used, and selective testing
            // cache lookup must be disabled so we only compute hashes.
            verify(generatorFactory)
                .testing(
                    config: .value(config),
                    testPlan: .value(nil),
                    includedTargets: .value([]),
                    excludedTargets: .value([]),
                    skipUITests: .value(false),
                    skipUnitTests: .value(false),
                    configuration: .value(nil),
                    ignoreBinaryCache: .value(true),
                    ignoreSelectiveTesting: .value(true),
                    cacheStorage: .any,
                    destination: .value(nil),
                    schemeName: .value(nil)
                )
                .called(1)
        }
    }

    @Test func run_outputsAWarning_when_noHashes() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let config = Tuist.test()
            let graph = Graph.test()
            let environment = MapperEnvironment()

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generator).loadWithEnvironment(path: .value(path), options: .any).willReturn((graph, environment))

            // When
            try await subject.run(path: path.pathString)

            // Then
            assertSnapshot(of: ui(), as: .lines)
        }
    }
}
