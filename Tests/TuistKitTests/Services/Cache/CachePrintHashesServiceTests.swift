import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistGraph
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CachePrintHashesServiceTests: TuistUnitTestCase {
    var subject: CachePrintHashesService!
    var generator: MockGenerator!
    var generatorFactory: MockGeneratorFactory!
    var cacheGraphContentHasher: MockCacheGraphContentHasher!
    var clock: Clock!
    var path: String!
    var configLoader: MockConfigLoader!

    override func setUp() {
        super.setUp()
        path = "/Test"
        generatorFactory = MockGeneratorFactory()
        generator = MockGenerator()
        generatorFactory.stubbedDefaultResult = generator

        cacheGraphContentHasher = MockCacheGraphContentHasher()
        clock = StubClock()

        configLoader = MockConfigLoader()
        configLoader.loadConfigStub = { _ in
            Config.test()
        }

        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        generator = nil
        generatorFactory = nil
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
        // When
        _ = try await subject.run(path: fullPath, xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertEqual(generator.invokedLoadParameterPath, try AbsolutePath(validating: fullPath))
    }

    func test_run_withoutPath_loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )

        // When
        _ = try await subject.run(path: nil, xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertEqual(generator.invokedLoadParameterPath, FileHandler.shared.currentPath)
    }

    func test_run_withRelativePath__loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )

        // When
        _ = try await subject.run(path: "RelativePath", xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertEqual(
            generator.invokedLoadParameterPath,
            try AbsolutePath(validating: "RelativePath", relativeTo: FileHandler.shared.currentPath)
        )
    }

    func test_run_loads_the_graph() async throws {
        // Given
        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )

        // When
        _ = try await subject.run(path: path, xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertEqual(generator.invokedLoadParameterPath, "/Test")
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
        generator.loadStub = { _ in graph }

        var invokedGraph: Graph?
        cacheGraphContentHasher.contentHashesStub = { graph, _, _, _ in
            invokedGraph = graph
            return [:]
        }

        // When
        _ = try await subject.run(path: path, xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertEqual(invokedGraph, graph)
    }

    func test_run_outputs_correct_hashes() async throws {
        // Given
        let target1 = GraphTarget.test(target: .test(name: "ShakiOne"))
        let target2 = GraphTarget.test(target: .test(name: "ShakiTwo"))
        cacheGraphContentHasher.contentHashesStub = { _, _, _, _ in
            [target1: "hash1", target2: "hash2"]
        }

        subject = CachePrintHashesService(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: cacheGraphContentHasher,
            clock: clock,
            configLoader: configLoader
        )

        // When
        _ = try await subject.run(path: path, xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertPrinterOutputContains("ShakiOne - hash1")
        XCTAssertPrinterOutputContains("ShakiTwo - hash2")
    }

    func test_run_gives_correct_artifact_type_to_hasher() async throws {
        // Given
        var xcframeworkOutputType: CacheOutputType?
        cacheGraphContentHasher.contentHashesStub = { _, _, cacheOutputType, _ in
            xcframeworkOutputType = cacheOutputType
            return [:]
        }

        // When
        _ = try await subject.run(path: path, xcframeworks: true, destination: [.device, .simulator], profile: nil)

        // Then
        XCTAssertEqual(xcframeworkOutputType, .xcframework([.device, .simulator]))

        // When
        _ = try await subject.run(path: path, xcframeworks: true, destination: .device, profile: nil)

        // Then
        XCTAssertEqual(xcframeworkOutputType, .xcframework(.device))

        // When
        _ = try await subject.run(path: path, xcframeworks: true, destination: .simulator, profile: nil)

        // Then
        XCTAssertEqual(xcframeworkOutputType, .xcframework(.simulator))

        // Given
        var frameworkOutputType: CacheOutputType?
        cacheGraphContentHasher.contentHashesStub = { _, _, cacheOutputType, _ in
            frameworkOutputType = cacheOutputType
            return [:]
        }

        // When
        _ = try await subject.run(path: path, xcframeworks: false, destination: [], profile: nil)

        // Then
        XCTAssertEqual(frameworkOutputType, .framework)
    }

    func test_run_gives_correct_cache_profile_type_to_hasher() async throws {
        // Given
        let profile: Cache.Profile = .test(
            name: "Simulator",
            configuration: "Debug",
            device: "iPhone 12",
            os: "15.0.0"
        )
        configLoader.loadConfigStub = { _ in
            Config.test(cache: .test(profiles: [profile]))
        }

        var invokedCacheProfile: TuistGraph.Cache.Profile?
        cacheGraphContentHasher.contentHashesStub = { _, cacheProfile, _, _ in
            invokedCacheProfile = cacheProfile
            return [:]
        }

        // When
        _ = try await subject.run(path: path, xcframeworks: false, destination: [], profile: "Simulator")

        // Then
        XCTAssertEqual(invokedCacheProfile, profile)
    }
}
