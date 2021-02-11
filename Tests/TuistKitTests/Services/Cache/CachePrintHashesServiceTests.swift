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
    var graphContentHasher: MockGraphContentHasher!
    var clock: Clock!
    var path: AbsolutePath!
    var generatorModelLoader: MockGeneratorModelLoader!

    override func setUp() {
        super.setUp()
        path = AbsolutePath("/Test")
        generator = MockGenerator()

        graphContentHasher = MockGraphContentHasher()
        clock = StubClock()

        generatorModelLoader = MockGeneratorModelLoader(basePath: path)
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test()
        }

        subject = CachePrintHashesService(generator: generator,
                                          graphContentHasher: graphContentHasher,
                                          clock: clock,
                                          generatorModelLoader: generatorModelLoader)
    }

    override func tearDown() {
        generator = nil
        graphContentHasher = nil
        clock = nil
        subject = nil
        super.tearDown()
    }

    func test_run_loads_the_graph() throws {
        // Given
        subject = CachePrintHashesService(generator: generator,
                                          graphContentHasher: graphContentHasher,
                                          clock: clock,
                                          generatorModelLoader: generatorModelLoader)

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertEqual(generator.invokedLoadParameterPath, path)
    }

    func test_run_content_hasher_gets_correct_graph() throws {
        // Given
        subject = CachePrintHashesService(generator: generator,
                                          graphContentHasher: graphContentHasher,
                                          clock: clock,
                                          generatorModelLoader: generatorModelLoader)
        let graph = Graph.test()
        generator.loadStub = { _ in graph }

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertEqual(graphContentHasher.invokedContentHashesParameters?.graph, graph)
    }

    func test_run_outputs_correct_hashes() throws {
        // Given
        let target1 = TargetNode.test(target: .test(name: "ShakiOne"))
        let target2 = TargetNode.test(target: .test(name: "ShakiTwo"))
        graphContentHasher.stubbedContentHashesResult = [target1: "hash1", target2: "hash2"]

        subject = CachePrintHashesService(generator: generator,
                                          graphContentHasher: graphContentHasher,
                                          clock: clock,
                                          generatorModelLoader: generatorModelLoader)

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertPrinterOutputContains("ShakiOne - hash1")
        XCTAssertPrinterOutputContains("ShakiTwo - hash2")
    }

    func test_run_gives_correct_artifact_type_to_hasher() throws {
        // When
        _ = try subject.run(path: path, xcframeworks: true, profile: nil)

        // Then
        XCTAssertEqual(graphContentHasher.invokedContentHashesParameters?.cacheOutputType, .xcframework)

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertEqual(graphContentHasher.invokedContentHashesParameters?.cacheOutputType, .framework)
    }

    func test_run_gives_correct_cache_profile_type_to_hasher() throws {
        // Given
        let profile: Cache.Profile = .test(name: "Simulator", configuration: "Debug")
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cache: .test(profiles: [profile]))
        }

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: "Simulator")

        // Then
        XCTAssertEqual(graphContentHasher.invokedContentHashesParameters?.cacheProfile, profile)
    }
}
