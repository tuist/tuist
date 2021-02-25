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
    var cacheGraphContentHasher: MockCacheGraphContentHasher!
    var clock: Clock!
    var path: AbsolutePath!
    var configLoader: MockConfigLoader!

    override func setUp() {
        super.setUp()
        path = AbsolutePath("/Test")
        generator = MockGenerator()

        cacheGraphContentHasher = MockCacheGraphContentHasher()
        clock = StubClock()

        configLoader = MockConfigLoader()
        configLoader.loadConfigStub = { _ in
            Config.test()
        }

        subject = CachePrintHashesService(
            generator: generator,
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

    func test_run_loads_the_graph() throws {
        // Given
        subject = CachePrintHashesService(generator: generator,
                                          cacheGraphContentHasher: cacheGraphContentHasher,
                                          clock: clock,
                                          configLoader: configLoader)

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertEqual(generator.invokedLoadParameterPath, path)
    }

    func test_run_content_hasher_gets_correct_graph() throws {
        // Given
        subject = CachePrintHashesService(generator: generator,
                                          cacheGraphContentHasher: cacheGraphContentHasher,
                                          clock: clock,
                                          configLoader: configLoader)
        let graph = Graph.test()
        generator.loadStub = { _ in graph }

        var invokedGraph: Graph?
        cacheGraphContentHasher.contentHashesStub = { graph, _, _ in
            invokedGraph = graph
            return [:]
        }

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertEqual(invokedGraph, graph)
    }

    func test_run_outputs_correct_hashes() throws {
        // Given
        let target1 = TargetNode.test(target: .test(name: "ShakiOne"))
        let target2 = TargetNode.test(target: .test(name: "ShakiTwo"))
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in
            [target1: "hash1", target2: "hash2"]
        }

        subject = CachePrintHashesService(generator: generator,
                                          cacheGraphContentHasher: cacheGraphContentHasher,
                                          clock: clock,
                                          configLoader: configLoader)

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertPrinterOutputContains("ShakiOne - hash1")
        XCTAssertPrinterOutputContains("ShakiTwo - hash2")
    }

    func test_run_gives_correct_artifact_type_to_hasher() throws {
        // Given
        var xcframeworkOutputType: CacheOutputType?
        cacheGraphContentHasher.contentHashesStub = { _, _, cacheOutputType in
            xcframeworkOutputType = cacheOutputType
            return [:]
        }

        // When
        _ = try subject.run(path: path, xcframeworks: true, profile: nil)

        // Then
        XCTAssertEqual(xcframeworkOutputType, .xcframework)

        // Given
        var frameworkOutputType: CacheOutputType?
        cacheGraphContentHasher.contentHashesStub = { _, _, cacheOutputType in
            frameworkOutputType = cacheOutputType
            return [:]
        }

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: nil)

        // Then
        XCTAssertEqual(frameworkOutputType, .framework)
    }

    func test_run_gives_correct_cache_profile_type_to_hasher() throws {
        // Given
        let profile: Cache.Profile = .test(name: "Simulator", configuration: "Debug")
        configLoader.loadConfigStub = { _ in
            Config.test(cache: .test(profiles: [profile]))
        }

        var invokedCacheProfile: TuistGraph.Cache.Profile?
        cacheGraphContentHasher.contentHashesStub = { _, cacheProfile, _ in
            invokedCacheProfile = cacheProfile
            return [:]
        }

        // When
        _ = try subject.run(path: path, xcframeworks: false, profile: "Simulator")

        // Then
        XCTAssertEqual(invokedCacheProfile, profile)
    }
}
