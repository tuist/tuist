import Foundation
import RxBlocking
import RxSwift
import TuistCore
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheMapperTests: TuistUnitTestCase {
    var cache: MockCacheStorage!
    var graphContentHasher: MockGraphContentHasher!
    var cacheGraphMutator: MockCacheGraphMutator!
    var subject: CacheMapper!
    var config: Config!

    override func setUp() {
        cache = MockCacheStorage()
        graphContentHasher = MockGraphContentHasher()
        cacheGraphMutator = MockCacheGraphMutator()
        config = .test()
        subject = CacheMapper(config: config,
                              cache: cache,
                              graphContentHasher: graphContentHasher,
                              sources: [],
                              cacheOutputType: .framework,
                              cacheGraphMutator: cacheGraphMutator,
                              queue: DispatchQueue.main)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        config = nil
        cache = nil
        graphContentHasher = nil
        cacheGraphMutator = nil
        subject = nil
    }

    func test_map_when_all_binaries_are_fetched_successfully() throws {
        let path = try temporaryPath()

        // Given
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cNode = TargetNode.test(target: cFramework, dependencies: [])
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cHash = "C"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bNode = TargetNode.test(target: bFramework, dependencies: [cNode])
        let bHash = "B"
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appNode = TargetNode.test(target: app, dependencies: [bNode])
        let appHash = "App"

        let inputGraph = Graph.test(name: "output", entryNodes: [appNode])
        let outputGraph = Graph.test(name: "output")

        let contentHashes = [
            cNode: cHash,
            bNode: bHash,
            appNode: appHash,
        ]
        graphContentHasher.stubbedContentHashesResult = contentHashes

        cache.existsStub = { hash in
            if hash == bHash { return true }
            if hash == cHash { return true }
            return false
        }

        cache.fetchStub = { hash in
            if hash == bHash { return bXCFrameworkPath }
            if hash == cHash { return cXCFrameworkPath }
            else { fatalError("unexpected call to fetch") }
        }
        cacheGraphMutator.stubbedMapResult = outputGraph

        // When
        let (got, _) = try subject.map(graph: inputGraph)

        // Then
        XCTAssertEqual(got.name, outputGraph.name)
    }

    func test_map_when_one_of_the_binaries_fails_cannot_be_fetched() throws {
        let path = try temporaryPath()

        // Given
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cNode = TargetNode.test(target: cFramework, dependencies: [])
        let cHash = "C"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bNode = TargetNode.test(target: bFramework, dependencies: [cNode])
        let bHash = "B"
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appNode = TargetNode.test(target: app, dependencies: [bNode])
        let appHash = "App"

        let inputGraph = Graph.test(name: "output", entryNodes: [appNode])
        let outputGraph = Graph.test(name: "output")

        let contentHashes = [
            cNode: cHash,
            bNode: bHash,
            appNode: appHash,
        ]
        let error = TestError("error downloading C")
        graphContentHasher.stubbedContentHashesResult = contentHashes

        cache.existsStub = { hash in
            if hash == bHash { return true }
            if hash == cHash { return true }
            return false
        }

        cache.fetchStub = { hash in
            if hash == bHash { return bXCFrameworkPath }
            if hash == cHash { throw error }
            else { fatalError("unexpected call to fetch") }
        }
        cacheGraphMutator.stubbedMapResult = outputGraph

        // Then
        XCTAssertThrowsSpecific(try subject.map(graph: inputGraph), error)
    }

    func test_map_forwards_correct_artifactType_to_hasher() throws {
        // Given
        subject = CacheMapper(config: config,
                              cache: cache,
                              graphContentHasher: graphContentHasher,
                              sources: [],
                              cacheOutputType: .xcframework,
                              cacheGraphMutator: cacheGraphMutator,
                              queue: DispatchQueue.main)

        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cNode = TargetNode.test(target: cFramework, dependencies: [])

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bNode = TargetNode.test(target: bFramework, dependencies: [cNode])

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appNode = TargetNode.test(target: app, dependencies: [bNode])

        let inputGraph = Graph.test(name: "output", entryNodes: [appNode])
        let outputGraph = Graph.test(name: "output")
        cacheGraphMutator.stubbedMapResult = outputGraph

        // When
        _ = try subject.map(graph: inputGraph)

        // Then
        XCTAssertEqual(graphContentHasher.invokedContentHashesParameters?.cacheOutputType, .xcframework)
    }
}
