import Foundation
import Mockable
import Path
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
    @Test func run_outputsTheHashes_fromMapperEnvironment() async throws {
        try await withMockedDependencies {
            // Given
            let fixture = makeFixture()
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

            given(fixture.configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(fixture.generator).loadWithEnvironment(path: .value(path), options: .any).willReturn((graph, environment))

            // When
            try await fixture.subject.run(path: path.pathString)

            // Then
            try TuistTest.expectLogs("AlphaTests - alpha-hash")
            try TuistTest.expectLogs("BetaTests - beta-hash")
        }
    }

    @Test func run_usesTheTestingGenerator_notTheDefaultOne() async throws {
        try await withMockedDependencies {
            // Given
            let fixture = makeFixture()
            let path = try AbsolutePath(validating: "/project/")
            let projectPath = try AbsolutePath(validating: "/project/Module")
            let config = Tuist.test()
            let graph = Graph.test()
            var environment = MapperEnvironment()
            environment.targetTestHashes = [projectPath: ["SomeTests": "hash"]]

            given(fixture.configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(fixture.generator).loadWithEnvironment(path: .value(path), options: .any).willReturn((graph, environment))

            // When
            try await fixture.subject.run(path: path.pathString)

            // Then: the testing generator (which uses CacheEE's TestsCacheGraphMapper for hashing,
            // matching what `tuist test` does at cache-fetch time) must be used, and selective testing
            // cache lookup must be disabled so we only compute hashes.
            verify(fixture.generatorFactory)
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
            let fixture = makeFixture()
            let path = try AbsolutePath(validating: "/project/")
            let config = Tuist.test()
            let graph = Graph.test()
            let environment = MapperEnvironment()

            given(fixture.configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(fixture.generator).loadWithEnvironment(path: .value(path), options: .any).willReturn((graph, environment))

            // When
            try await fixture.subject.run(path: path.pathString)

            // Then
            let output = ui()
            #expect(output.contains("The following items may need attention:"))
            #expect(output.contains("The project contains no hasheable targets for selective testing."))
        }
    }

    private func makeFixture() -> Fixture {
        let generatorFactory = MockGeneratorFactorying()
        let generator = MockGenerating()
        let cacheStorageFactory = MockCacheStorageFactorying()
        let cacheStorage = MockCacheStoring()
        let configLoader = MockConfigLoading()

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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        return Fixture(
            subject: HashSelectiveTestingCommandService(
                generatorFactory: generatorFactory,
                cacheStorageFactory: cacheStorageFactory,
                configLoader: configLoader
            ),
            generator: generator,
            generatorFactory: generatorFactory,
            configLoader: configLoader
        )
    }

    private struct Fixture {
        let subject: HashSelectiveTestingCommandService
        let generator: MockGenerating
        let generatorFactory: MockGeneratorFactorying
        let configLoader: MockConfigLoading
    }
}
