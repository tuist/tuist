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
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct HashSelectiveTestingCommandServiceTests {
    private var subject: HashSelectiveTestingCommandService!
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var configLoader: MockConfigLoading!
    private var selectiveTestingGraphHasher: MockSelectiveTestingGraphHashing!

    init() {
        generatorFactory = MockGeneratorFactorying()
        generator = .init()
        given(generatorFactory)
            .defaultGenerator(config: .any, includedTargets: .any)
            .willReturn(generator)

        configLoader = .init()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        selectiveTestingGraphHasher = MockSelectiveTestingGraphHashing()

        subject = HashSelectiveTestingCommandService(
            generatorFactory: generatorFactory,
            configLoader: configLoader,
            selectiveTestingGraphHasher: selectiveTestingGraphHasher
        )
    }

    @Test func run_outputsTheHashes() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let config = Tuist.test()
            let graph = Graph.test()
            let target = GraphTarget.test()

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).defaultGenerator(
                config: .value(config),
                includedTargets: .value([])
            ).willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(selectiveTestingGraphHasher).hash(
                graph: .value(graph),
                additionalStrings: .value([])
            ).willReturn([target: .test(hash: "hash")])

            // When
            try await subject.run(path: path.pathString)

            // Then
            try TuistTest.expectLogs("Target - hash")
        }
    }

    @Test func run_outputsAWarning_when_noHashes() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let config = Tuist.test()
            let graph = Graph.test()

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).defaultGenerator(
                config: .value(config),
                includedTargets: .value([])
            ).willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(selectiveTestingGraphHasher).hash(
                graph: .value(graph),
                additionalStrings: .value([])
            ).willReturn([:])

            // When
            try await subject.run(path: path.pathString)

            // Then
            assertSnapshot(of: ui(), as: .lines)
        }
    }
}
