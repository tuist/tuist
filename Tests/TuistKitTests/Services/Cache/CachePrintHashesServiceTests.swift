import Foundation
import Mockable
import MockableTest
import Path
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class CachePrintHashesServiceTests: TuistUnitTestCase {
    var subject: CachePrintHashesService!
    var generator: MockGenerating!
    var generatorFactory: MockGeneratorFactorying!
    var cacheGraphContentHasher: MockCacheGraphContentHashing!
    var clock: Clock!
    var path: String!
    var configLoader: MockConfigLoading!

    override func setUp() {
        super.setUp()
        path = "/Test"
        generatorFactory = MockGeneratorFactorying()
        generator = .init()
        given(generatorFactory)
            .defaultGenerator(config: .any)
            .willReturn(generator)

        cacheGraphContentHasher = MockCacheGraphContentHashing()
        clock = StubClock()

        configLoader = .init()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        generator = nil
        cacheGraphContentHasher = nil
        clock = nil
        subject = nil
        super.tearDown()
    }

    func test_run_withFullPath_loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
        let fullPath = FileHandler.shared.currentPath.pathString + "/full/path"
        given(cacheGraphContentHasher)
            .contentHashes(for: .any, configuration: .any, config: .any, excludedTargets: .any)
            .willReturn([:])
        given(generator)
            .load(path: .any)
            .willReturn(.test())

        // When
        _ = try await subject.run(path: fullPath, configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(try AbsolutePath(validating: fullPath)))
            .called(1)
    }

    func test_run_withoutPath_loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
        given(cacheGraphContentHasher)
            .contentHashes(for: .any, configuration: .any, config: .any, excludedTargets: .any)
            .willReturn([:])
        given(generator)
            .load(path: .any)
            .willReturn(.test())

        // When
        _ = try await subject.run(path: nil, configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(FileHandler.shared.currentPath))
            .called(1)
    }

    func test_run_withRelativePath__loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
        given(cacheGraphContentHasher)
            .contentHashes(for: .any, configuration: .any, config: .any, excludedTargets: .any)
            .willReturn([:])
        given(generator)
            .load(path: .any)
            .willReturn(.test())

        // When
        _ = try await subject.run(path: "RelativePath", configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(try AbsolutePath(validating: "RelativePath", relativeTo: FileHandler.shared.currentPath)))
            .called(1)
    }

    func test_run_loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
        given(cacheGraphContentHasher)
            .contentHashes(for: .any, configuration: .any, config: .any, excludedTargets: .any)
            .willReturn([:])
        given(generator)
            .load(path: .any)
            .willReturn(.test())

        // When
        _ = try await subject.run(path: path, configuration: nil)

        // Then
        verify(generator)
            .load(path: .value(try AbsolutePath(validating: "/Test")))
            .called(1)
    }

    func test_run_content_hasher_gets_correct_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
        let graph = Graph.test()
        given(generator)
            .load(path: .any)
            .willReturn(graph)

        given(cacheGraphContentHasher)
            .contentHashes(for: .value(graph), configuration: .any, config: .any, excludedTargets: .any)
            .willReturn([:])

        // When / Then
        _ = try await subject.run(path: path, configuration: nil)
    }

    func test_run_outputs_correct_hashes() async throws {
        // Given
        let target1 = GraphTarget.test(target: .test(name: "ShakiOne"))
        let target2 = GraphTarget.test(target: .test(name: "ShakiTwo"))
        given(cacheGraphContentHasher)
            .contentHashes(for: .any, configuration: .any, config: .any, excludedTargets: .any)
            .willReturn([target1: "hash1", target2: "hash2"])

        given(generator)
            .load(path: .any)
            .willReturn(.test())

        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )

        // When
        _ = try await subject.run(path: path, configuration: nil)

        // Then
        XCTAssertPrinterOutputContains("ShakiOne - hash1")
        XCTAssertPrinterOutputContains("ShakiTwo - hash2")
    }

    func test_run_gives_correct_configuration_type_to_hasher() async throws {
        // Given
        given(cacheGraphContentHasher)
            .contentHashes(for: .any, configuration: .value("Debug"), config: .any, excludedTargets: .any)
            .willReturn([:])

        given(generator)
            .load(path: .any)
            .willReturn(.test())

        // When / Then
        _ = try await subject.run(path: path, configuration: "Debug")
    }
}
