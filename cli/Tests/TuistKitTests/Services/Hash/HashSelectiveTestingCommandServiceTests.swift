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

/// Pins the wiring change behind the fix for `tuist hash selective-testing` emitting hashes
/// that did not match the keys used by `tuist test --build-only` for cache lookup.
///
/// Pre-fix, the command loaded the graph via `GeneratorFactory.defaultGenerator` and hashed
/// it through `SelectiveTestingGraphHasher`. The testing pipeline (`generatorFactory.testing`)
/// uses a different pre-hash mapper set (e.g. `ExternalProjectsPlatformNarrowerGraphMapper`
/// running before `FocusTargets`/`TreeShake`), so targets whose dependency closure went
/// through those mappers ended up with different content hashes.
///
/// These tests would fail on the pre-fix code:
///  - `run_usesTheTestingGenerator_notTheDefaultOne` verifies the routing change — the command
///    must now invoke `generatorFactory.testing(...)` with `ignoreSelectiveTesting: true` and
///    `ignoreBinaryCache: true`.
///  - `run_outputsTheHashes_fromMapperEnvironment` stubs the new `loadWithEnvironment` hook
///    on `Generating` and verifies the command surfaces hashes from
///    `MapperEnvironment.targetTestHashes` (populated by `TestsCacheGraphMapper`) instead of
///    re-running a separate hasher.
///
/// The downstream contract (that `TestsCacheGraphMapper` populates `targetTestHashes` even
/// when `ignoreSelectiveTesting: true`) is pinned by
/// `TuistCacheEETests/TestsCacheMapperTests/test_when_ignore_selective_testing`. The
/// mappers that transform pre-hash graph state — and thus generate the divergence on real
/// projects — are pinned individually by
/// `TuistDependenciesTests/ExternalProjectsPlatformNarrowerGraphMapperTests` and
/// `TuistDependenciesTests/PruneOrphanExternalTargetsGraphMapperTests`.
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
