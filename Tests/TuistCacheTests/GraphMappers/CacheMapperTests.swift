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
    var cacheGraphMapper: MockCacheGraphMapper!
    var subject: CacheMapper!

    override func setUp() {
        cache = MockCacheStorage()
        graphContentHasher = MockGraphContentHasher()
        cacheGraphMapper = MockCacheGraphMapper()
        subject = CacheMapper(cache: cache,
                              graphContentHasher: graphContentHasher,
                              cacheGraphMapper: cacheGraphMapper,
                              queue: DispatchQueue.main)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        cache = nil
        graphContentHasher = nil
        cacheGraphMapper = nil
        subject = nil
    }

    func test_map_when_all_xcframeworks_are_fetched_successfully() throws {
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
        graphContentHasher.contentHashesStub = contentHashes

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
        cacheGraphMapper.mapStub = .success(outputGraph)

        // When
        let (got, _) = try subject.map(graph: inputGraph)

        // Then
        XCTAssertEqual(got.name, outputGraph.name)
    }

    func test_map_when_one_of_the_xcframeworks_fails_cannot_be_fetched() throws {
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
        let error = TestError("error downloading C")
        graphContentHasher.contentHashesStub = contentHashes

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
        cacheGraphMapper.mapStub = .success(outputGraph)

        // Then
        XCTAssertThrowsSpecific(try subject.map(graph: inputGraph), error)
    }
}
