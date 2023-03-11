import Foundation
import TSCBasic
import TuistCache
import TuistGraph
import XCTest

@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheGraphContentHasherTests: TuistUnitTestCase {
    var graphContentHasher: MockGraphContentHasher!
    var contentHasher: MockContentHasher!
    var subject: CacheGraphContentHasher!

    override func setUp() {
        super.setUp()

        graphContentHasher = MockGraphContentHasher()
        contentHasher = MockContentHasher()
        system.swiftlangVersionStub = {
            "5.4.2"
        }
        subject = CacheGraphContentHasher(
            graphContentHasher: graphContentHasher,
            cacheProfileContentHasher: CacheProfileContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher
        )
    }

    override func tearDown() {
        graphContentHasher = nil
        contentHasher = nil
        subject = nil
        super.tearDown()
    }

    func test_contentHashes_when_no_excluded_targets_all_hashes_are_computed() throws {
        var contentHashesCalled = false
        let includedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Included", product: .framework),
            project: Project.test()
        )
        graphContentHasher.contentHashesStub = { _, filter, _ in
            contentHashesCalled = true
            XCTAssertTrue(filter(includedTarget))
            return [:]
        }
        _ = try subject.contentHashes(
            for: Graph.test(),
            cacheProfile: TuistGraph.Cache.Profile(name: "Development", configuration: "Debug"),
            cacheOutputType: .xcframework([.device, .simulator]),
            excludedTargets: []
        )
        XCTAssertTrue(contentHashesCalled)
    }

    func test_contentHashes_when_excluded_targets_excluded_hashes_are_not_computed() throws {
        var contentHashesCalled = false
        let excludedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Excluded", product: .framework),
            project: Project.test()
        )
        let includedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Included", product: .framework),
            project: Project.test()
        )
        graphContentHasher.contentHashesStub = { _, filter, _ in
            contentHashesCalled = true
            XCTAssertTrue(filter(includedTarget))
            XCTAssertFalse(filter(excludedTarget))
            return [:]
        }
        _ = try subject.contentHashes(
            for: Graph.test(),
            cacheProfile: TuistGraph.Cache.Profile(name: "Development", configuration: "Debug"),
            cacheOutputType: .xcframework([.device, .simulator]),
            excludedTargets: ["Excluded"]
        )
        XCTAssertTrue(contentHashesCalled)
    }

    func test_contentHashes_when_excluded_targets_resources_hashes_are_not_computed() throws {
        let project = Project.test()

        var contentHashesCalled = false
        let excludedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Excluded", product: .framework),
            project: project
        )
        let excludedTargetResource = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "\(project.name)_Excluded", product: .bundle),
            project: project
        )
        let includedTarget = GraphTarget(
            path: "/Project/Path",
            target: Target.test(name: "Included", product: .framework),
            project: Project.test()
        )
        graphContentHasher.contentHashesStub = { _, filter, _ in
            contentHashesCalled = true
            XCTAssertTrue(filter(includedTarget))
            XCTAssertFalse(filter(excludedTarget))
            XCTAssertFalse(filter(excludedTargetResource))
            return [:]
        }
        _ = try subject.contentHashes(
            for: Graph.test(),
            cacheProfile: TuistGraph.Cache.Profile(name: "Development", configuration: "Debug"),
            cacheOutputType: .xcframework([.device, .simulator]),
            excludedTargets: ["Excluded"]
        )
        XCTAssertTrue(contentHashesCalled)
    }
}
