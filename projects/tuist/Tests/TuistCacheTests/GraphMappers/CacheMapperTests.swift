import Foundation
import RxBlocking
import RxSwift
import TuistCore
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class CacheMapperTests: TuistUnitTestCase {
    var cache: MockCacheStorage!
    var cacheGraphContentHasher: MockCacheGraphContentHasher!
    var cacheGraphMutator: MockCacheGraphMutator!
    var subject: CacheMapper!
    var config: Config!

    override func setUp() {
        cache = MockCacheStorage()
        cacheGraphContentHasher = MockCacheGraphContentHasher()
        cacheGraphMutator = MockCacheGraphMutator()
        config = .test()
        subject = CacheMapper(
            config: config,
            cache: cache,
            cacheGraphContentHasher: cacheGraphContentHasher,
            sources: [],
            cacheProfile: .test(),
            cacheOutputType: .framework,
            cacheGraphMutator: cacheGraphMutator,
            queue: DispatchQueue.main
        )
        super.setUp()
    }

    override func tearDown() {
        config = nil
        cache = nil
        cacheGraphContentHasher = nil
        cacheGraphMutator = nil
        subject = nil
        super.tearDown()
    }

    func test_map_when_all_binaries_are_fetched_successfully() throws {
        let path = try temporaryPath()
        let project = Project.test(path: path)

        // Given
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = ValueGraphTarget.test(path: path, target: cFramework)
        let cXCFrameworkPath = path.appending(component: "C.xcframework")
        let cHash = "C"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = ValueGraphTarget.test(path: path, target: bFramework)
        let bHash = "B"
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appGraphTarget = ValueGraphTarget.test(path: path, target: app)
        let appHash = "App"

        let inputGraph = ValueGraph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: app.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )
        let outputGraph = ValueGraph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )

        let contentHashes = [
            cGraphTarget: cHash,
            bGraphTarget: bHash,
            appGraphTarget: appHash,
        ]
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in
            contentHashes
        }

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
        XCTAssertEqual(
            got,
            outputGraph
        )
    }

    func test_map_when_one_of_the_binaries_fails_cannot_be_fetched() throws {
        let path = try temporaryPath()
        let project = Project.test(path: path)

        // Given
        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = ValueGraphTarget.test(path: path, target: cFramework)
        let cHash = "C"

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = ValueGraphTarget.test(path: path, target: bFramework)
        let bHash = "B"
        let bXCFrameworkPath = path.appending(component: "B.xcframework")

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appGraphTarget = ValueGraphTarget.test(path: path, target: app)
        let appHash = "App"

        let inputGraph = ValueGraph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: app.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )
        let outputGraph = ValueGraph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )

        let contentHashes = [
            cGraphTarget: cHash,
            bGraphTarget: bHash,
            appGraphTarget: appHash,
        ]
        let error = TestError("error downloading C")
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in
            contentHashes
        }

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
        let path = try temporaryPath()
        let project = Project.test(path: path)

        subject = CacheMapper(
            config: config,
            cache: cache,
            cacheGraphContentHasher: cacheGraphContentHasher,
            sources: [],
            cacheProfile: .test(),
            cacheOutputType: .xcframework,
            cacheGraphMutator: cacheGraphMutator,
            queue: DispatchQueue.main
        )

        let cFramework = Target.test(name: "C", platform: .iOS, product: .framework)
        let cGraphTarget = ValueGraphTarget.test(path: path, target: cFramework)

        let bFramework = Target.test(name: "B", platform: .iOS, product: .framework)
        let bGraphTarget = ValueGraphTarget.test(path: path, target: bFramework)

        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let appGraphTarget = ValueGraphTarget.test(path: path, target: app)

        let inputGraph = ValueGraph.test(
            name: "input",
            projects: [path: project],
            dependencies: [
                .target(name: bFramework.name, path: bGraphTarget.path): [
                    .target(name: cFramework.name, path: cGraphTarget.path),
                ],
                .target(name: app.name, path: appGraphTarget.path): [
                    .target(name: bFramework.name, path: bGraphTarget.path),
                ],
            ]
        )
        let outputGraph = ValueGraph.test(
            name: "output",
            projects: inputGraph.projects,
            dependencies: inputGraph.dependencies
        )
        cacheGraphMutator.stubbedMapResult = outputGraph

        var invokedCacheOutputType: CacheOutputType?
        var invokedCacheProfile: TuistGraph.Cache.Profile?
        cacheGraphContentHasher.contentHashesStub = { _, cacheProfile, cacheOutputType in
            invokedCacheOutputType = cacheOutputType
            invokedCacheProfile = cacheProfile
            return [:]
        }

        // When
        _ = try subject.map(graph: inputGraph)

        // Then
        XCTAssertEqual(invokedCacheProfile, .test())
        XCTAssertEqual(invokedCacheOutputType, .xcframework)
    }
}
