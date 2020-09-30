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
    var frameworkBuilder: MockFrameworkBuilder!
    var manifestLoader: MockManifestLoader!
    var cache: MockCacheStorage!
    var subject: CacheController!
    var config: Config!

    override func setUp() {
        generator = MockProjectGenerator()
        frameworkBuilder = MockFrameworkBuilder()
        cache = MockCacheStorage()
        manifestLoader = MockManifestLoader()
        graphContentHasher = MockGraphContentHasher()
        config = .test()
        subject = CacheController(cache: cache,
                                  artifactBuilder: frameworkBuilder,
                                  generator: generator,
                                  graphContentHasher: graphContentHasher)

        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        frameworkBuilder = nil
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
        let aFrameworkPath = path.appending(component: "A.framework")
        let bFrameworkPath = path.appending(component: "B.framework")
        try FileHandler.shared.createFolder(aFrameworkPath)
        try FileHandler.shared.createFolder(bFrameworkPath)

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
        graphContentHasher.stubbedContentHashesResult = nodeWithHashes

        frameworkBuilder.stubbedBuildWorkspacePathResult = { _xcworkspacePath, target in
            switch (_xcworkspacePath, target) {
            case (xcworkspacePath, aTarget): return .success([aFrameworkPath])
            case (xcworkspacePath, bTarget): return .success([bFrameworkPath])
            default: return .failure(TestError("Received invalid Xcode project path or target"))
            }
        }
        frameworkBuilder.stubbedCacheOutputType = .xcframework

        try subject.cache(path: path)

        // Then
        XCTAssertPrinterOutputContains("""
        Hashing cacheable frameworks
        Building cacheable frameworks as xcframeworks
        All cacheable frameworks have been cached successfully as xcframeworks
        """)
        XCTAssertFalse(FileHandler.shared.exists(aFrameworkPath))
        XCTAssertFalse(FileHandler.shared.exists(bFrameworkPath))
    }
}
