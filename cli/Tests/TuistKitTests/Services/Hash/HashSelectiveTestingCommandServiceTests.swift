import Foundation
import Mockable
import Path
import SnapshotTesting
import Testing
import TuistCache
import TuistCore
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
    private var cacheGraphContentHasher: MockCacheGraphContentHashing!
    private var path: String!
    private var configLoader: MockConfigLoading!
    private var manifestLoader: MockManifestLoading!
    private var manifestGraphLoader: MockManifestGraphLoading!
    private var xcodeGraphMapper: MockXcodeGraphMapping!
    private var selectiveTestingGraphHasher: MockSelectiveTestingGraphHashing!

    init() {
        path = "/Test"
        generatorFactory = MockGeneratorFactorying()
        generator = .init()
        given(generatorFactory)
            .defaultGenerator(config: .any, includedTargets: .any)
            .willReturn(generator)

        cacheGraphContentHasher = MockCacheGraphContentHashing()

        configLoader = .init()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        manifestLoader = MockManifestLoading()
        manifestGraphLoader = MockManifestGraphLoading()
        xcodeGraphMapper = MockXcodeGraphMapping()
        selectiveTestingGraphHasher = MockSelectiveTestingGraphHashing()

        subject = HashSelectiveTestingCommandService(
            generatorFactory: generatorFactory,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            xcodeGraphMapper: xcodeGraphMapper,
            selectiveTestingGraphHasher: selectiveTestingGraphHasher
        )
    }

    @Test func run_outputsTheHashes_when_generatedProject() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let passthroughXcodebuildArguments = ["-configuration", "Debug"]
            let config = Tuist.test()
            let graph = Graph.test()
            let target = GraphTarget.test()

            given(manifestLoader).hasRootManifest(at: .value(path)).willReturn(true)
            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).defaultGenerator(
                config: .value(config),
                includedTargets: .value([])
            ).willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(selectiveTestingGraphHasher).hash(
                graph: .value(graph),
                additionalStrings: .value(
                    XcodeBuildTestCommandService
                        .additionalHashableStringsFromXcodebuildPassthroughArguments(passthroughXcodebuildArguments)
                )
            ).willReturn([target: .test(hash: "hash")])

            // When
            try await subject.run(
                path: path.pathString,
                passthroughXcodebuildArguments: passthroughXcodebuildArguments
            )

            // Then
            try TuistTest.expectLogs("Target - hash")
        }
    }

    @Test func run_outputsAWarning_when_generatedProject_and_noHashes() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let passthroughXcodebuildArguments = ["-configuration", "Debug"]
            let config = Tuist.test()
            let graph = Graph.test()

            given(manifestLoader).hasRootManifest(at: .value(path)).willReturn(true)
            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).defaultGenerator(
                config: .value(config),
                includedTargets: .value([])
            ).willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(selectiveTestingGraphHasher).hash(
                graph: .value(graph),
                additionalStrings: .value(
                    XcodeBuildTestCommandService
                        .additionalHashableStringsFromXcodebuildPassthroughArguments(passthroughXcodebuildArguments)
                )
            ).willReturn([:])

            // When
            try await subject.run(
                path: path.pathString,
                passthroughXcodebuildArguments: passthroughXcodebuildArguments
            )

            // Then
            assertSnapshot(of: ui(), as: .lines)
        }
    }

    @Test func run_outputsTheHashes_when_xcodeProject() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let passthroughXcodebuildArguments = ["-configuration", "Debug"]
            let graph = Graph.test()
            let target = GraphTarget.test()

            given(manifestLoader).hasRootManifest(at: .value(path)).willReturn(false)
            given(xcodeGraphMapper).map(at: .value(path)).willReturn(graph)
            given(selectiveTestingGraphHasher).hash(
                graph: .value(graph),
                additionalStrings: .value(
                    XcodeBuildTestCommandService
                        .additionalHashableStringsFromXcodebuildPassthroughArguments(passthroughXcodebuildArguments)
                )
            ).willReturn([target: .test(hash: "hash")])

            // When
            try await subject.run(
                path: path.pathString,
                passthroughXcodebuildArguments: passthroughXcodebuildArguments
            )

            // Then
            try TuistTest.expectLogs("Target - hash")
        }
    }

    @Test func run_outputsAWarning_when_xcodeProject_and_noHashes() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project/")
            let passthroughXcodebuildArguments = ["-configuration", "Debug"]
            let graph = Graph.test()

            given(manifestLoader).hasRootManifest(at: .value(path)).willReturn(false)
            given(xcodeGraphMapper).map(at: .value(path)).willReturn(graph)
            given(selectiveTestingGraphHasher).hash(
                graph: .value(graph),
                additionalStrings: .value(
                    XcodeBuildTestCommandService
                        .additionalHashableStringsFromXcodebuildPassthroughArguments(passthroughXcodebuildArguments)
                )
            ).willReturn([:])

            // When
            try await subject.run(
                path: path.pathString,
                passthroughXcodebuildArguments: passthroughXcodebuildArguments
            )

            // Then
            assertSnapshot(of: ui(), as: .lines)
        }
    }
}
