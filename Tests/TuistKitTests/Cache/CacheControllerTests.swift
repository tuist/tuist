import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CacheControllerTests: TuistUnitTestCase {
    var generator: MockProjectGenerator!
    var graphContentHasher: MockGraphContentHasher!
    var xcframeworkBuilder: MockXCFrameworkBuilder!
    var manifestLoader: MockManifestLoader!
    var cache: MockCacheStorage!
    var subject: CacheController!
    var config: Config!

    override func setUp() {
        generator = MockProjectGenerator()
        xcframeworkBuilder = MockXCFrameworkBuilder()
        cache = MockCacheStorage()
        manifestLoader = MockManifestLoader()
        graphContentHasher = MockGraphContentHasher()
        config = .test()
        subject = CacheController(generator: generator,
                                  xcframeworkBuilder: xcframeworkBuilder,
                                  cache: cache,
                                  graphContentHasher: graphContentHasher)

        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        xcframeworkBuilder = nil
        graphContentHasher = nil
        manifestLoader = nil
        cache = nil
        subject = nil
        config = nil
    }

    func test_cache_builds_and_caches_the_frameworks() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let project = Project.test(path: path, name: "Cache")
        let aTarget = Target.test(name: "A")
        let bTarget = Target.test(name: "B")
        let axcframeworkPath = path.appending(component: "A.xcframework")
        let bxcframeworkPath = path.appending(component: "B.xcframework")
        try FileHandler.shared.createFolder(axcframeworkPath)
        try FileHandler.shared.createFolder(bxcframeworkPath)

        let nodeWithHashes = [
            TargetNode.test(project: project, target: aTarget): "A_HASH",
            TargetNode.test(project: project, target: bTarget): "B_HASH",
        ]
        let graph = Graph.test(projects: [project],
                               targets: nodeWithHashes.keys.reduce(into: [project.path: [TargetNode]()]) { $0[project.path]?.append($1) })

        manifestLoader.manifestsAtStub = { (loadPath: AbsolutePath) -> Set<Manifest> in
            XCTAssertEqual(loadPath, path)
            return Set(arrayLiteral: .project)
        }
        generator.generateWithGraphStub = { (loadPath, _) -> (AbsolutePath, Graph) in
            XCTAssertEqual(loadPath, path)
            return (xcworkspacePath, graph)
        }
        graphContentHasher.contentHashesStub = nodeWithHashes

        xcframeworkBuilder.buildWorkspaceStub = { _xcworkspacePath, target in
            switch (_xcworkspacePath, target) {
            case (xcworkspacePath, aTarget): return .success(axcframeworkPath)
            case (xcworkspacePath, bTarget): return .success(bxcframeworkPath)
            default: return .failure(TestError("Received invalid Xcode project path or target"))
            }
        }

        try subject.cache(path: path, config: config)

        // Then
        XCTAssertPrinterOutputContains("""
        Hashing cacheable frameworks
        All cacheable frameworks have been cached successfully
        """)
        XCTAssertFalse(FileHandler.shared.exists(axcframeworkPath))
        XCTAssertFalse(FileHandler.shared.exists(bxcframeworkPath))
    }
}
