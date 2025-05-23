import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XcodeGraph

@testable import TuistKit

struct HashCacheCommandServiceTests {
    private var subject: HashCacheCommandService!
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var cacheGraphContentHasher: MockCacheGraphContentHashing!
    private var clock: Clock!
    private var path: String!
    private var configLoader: MockConfigLoading!
    private var manifestLoader: MockManifestLoading!
    private var manifestGraphLoader: MockManifestGraphLoading!
    private var xcodeGraphMapper: MockXcodeGraphMapping!

    init() {
        path = "/Test"
        generatorFactory = MockGeneratorFactorying()
        generator = .init()
        given(generatorFactory)
            .defaultGenerator(config: .any, includedTargets: .any)
            .willReturn(generator)

        cacheGraphContentHasher = MockCacheGraphContentHashing()
        clock = StubClock()

        configLoader = .init()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        manifestLoader = MockManifestLoading()
        manifestGraphLoader = MockManifestGraphLoading()
        xcodeGraphMapper = MockXcodeGraphMapping()

        subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
    }

    @Test func errors_when_notGeneratedProject() async throws {
        // Given
        let subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
        let fullPath = FileHandler.shared.currentPath.pathString + "/full/path"
        let graph = Graph.test()
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(xcodeGraphMapper).map(at: .value(try AbsolutePath(validating: fullPath))).willReturn(
            graph
        )

        given(manifestLoader).hasRootManifest(at: .value(try AbsolutePath(validating: fullPath)))
            .willReturn(false)

        // When
        await #expect(
            throws: HashCacheCommandServiceError.generatedProjectNotFound(
                try AbsolutePath(validating: fullPath)
            ),
            performing: {
                try await subject.run(path: fullPath, configuration: nil)
            }
        )
    }

    @Test func test_run_withFullPath_loads_the_graph() async throws {
        // Given
        let subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
        let fullPath = FileHandler.shared.currentPath.pathString + "/full/path"
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(generator)
            .load(path: .any, disableSandbox: .any)
            .willReturn(.test())
        given(manifestLoader).hasRootManifest(at: .value(try AbsolutePath(validating: fullPath)))
            .willReturn(true)

        // When
        _ = try await subject.run(path: fullPath, configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(try AbsolutePath(validating: fullPath)), disableSandbox: .any)
            .called(1)
    }

    @Test func test_run_withoutPath_loads_the_graph() async throws {
        // Given
        let subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(generator)
            .load(path: .any, disableSandbox: .any)
            .willReturn(.test())
        given(manifestLoader).hasRootManifest(at: .any).willReturn(true)

        // When
        _ = try await subject.run(path: nil, configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(FileHandler.shared.currentPath), disableSandbox: .any)
            .called(1)
    }

    @Test func test_run_withRelativePath__loads_the_graph() async throws {
        // Given
        let subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(generator)
            .load(path: .any, disableSandbox: .any)
            .willReturn(.test())
        given(manifestLoader).hasRootManifest(at: .any).willReturn(true)

        // When
        _ = try await subject.run(path: "RelativePath", configuration: nil)

        // Then
        verify(generator)
            .load(
                path: .value(
                    try AbsolutePath(
                        validating: "RelativePath", relativeTo: FileHandler.shared.currentPath
                    )
                ),
                disableSandbox: .any
            )
            .called(1)
    }

    @Test func test_run_loads_the_graph() async throws {
        // Given
        let subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(generator)
            .load(path: .any, disableSandbox: .any)
            .willReturn(.test())
        given(manifestLoader).hasRootManifest(at: .any).willReturn(true)

        // When
        _ = try await subject.run(path: path, configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(try AbsolutePath(validating: "/Test")), disableSandbox: .any)
            .called(1)
    }

    @Test func test_run_content_hasher_gets_correct_graph() async throws {
        // Given
        let subject = HashCacheCommandService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
        let graph = Graph.test()
        given(generator)
            .load(path: .any, disableSandbox: .any)
            .willReturn(graph)

        given(cacheGraphContentHasher)
            .contentHashes(
                for: .value(graph),
                configuration: .any,
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(manifestLoader).hasRootManifest(at: .any).willReturn(true)

        // When / Then
        _ = try await subject.run(path: path, configuration: nil)
    }

    @Test func test_run_outputs_correct_hashes() async throws {
        try await withTestingDependencies {
            // Given
            let target1 = GraphTarget.test(target: .test(name: "ShakiOne"))
            let target2 = GraphTarget.test(target: .test(name: "ShakiTwo"))
            given(cacheGraphContentHasher)
                .contentHashes(
                    for: .any,
                    configuration: .any,
                    defaultConfiguration: .any,
                    excludedTargets: .any,
                    destination: .any
                )
                .willReturn([target1: "hash1", target2: "hash2"])

            given(generator)
                .load(path: .any, disableSandbox: .any)
                .willReturn(.test())
            given(manifestLoader).hasRootManifest(at: .any).willReturn(true)

            let subject = HashCacheCommandService(
                generatorFactory: generatorFactory,
                cacheGraphContentHasher: cacheGraphContentHasher,
                clock: clock,
                configLoader: configLoader,
                manifestLoader: manifestLoader,
                manifestGraphLoader: manifestGraphLoader
            )

            // When
            _ = try await subject.run(path: path, configuration: nil)

            // Then
            try expectLogs("ShakiOne - hash1")
            try expectLogs("ShakiTwo - hash2")
        }
    }

    func test_run_gives_correct_configuration_type_to_hasher() async throws {
        // Given
        given(cacheGraphContentHasher)
            .contentHashes(
                for: .any,
                configuration: .value("Debug"),
                defaultConfiguration: .any,
                excludedTargets: .any,
                destination: .any
            )
            .willReturn([:])
        given(manifestLoader).hasRootManifest(at: .any).willReturn(true)

        given(generator)
            .load(path: .any, disableSandbox: .any)
            .willReturn(.test())

        // When / Then
        _ = try await subject.run(path: path, configuration: "Debug")
    }
}
