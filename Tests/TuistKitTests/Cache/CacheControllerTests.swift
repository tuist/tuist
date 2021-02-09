import Foundation
import TSCBasic
import TuistCache
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistKit
@testable import TuistSupportTesting

final class CacheControllerTests: TuistUnitTestCase {
    var generator: MockGenerator!
    var cacheGraphContentHasher: MockCacheGraphContentHasher!
    var artifactBuilder: MockCacheArtifactBuilder!
    var manifestLoader: MockManifestLoader!
    var cache: MockCacheStorage!
    var subject: CacheController!
    var projectGeneratorProvider: MockCacheControllerProjectGeneratorProvider!
    var config: Config!
    var cacheGraphLinter: MockCacheGraphLinter!

    override func setUp() {
        generator = MockGenerator()
        artifactBuilder = MockCacheArtifactBuilder()
        cache = MockCacheStorage()
        manifestLoader = MockManifestLoader()
        cacheGraphContentHasher = MockCacheGraphContentHasher()
        config = .test()
        projectGeneratorProvider = MockCacheControllerProjectGeneratorProvider()
        projectGeneratorProvider.stubbedGeneratorResult = generator
        cacheGraphLinter = MockCacheGraphLinter()
        subject = CacheController(cache: cache,
                                  artifactBuilder: artifactBuilder,
                                  projectGeneratorProvider: projectGeneratorProvider,
                                  cacheGraphContentHasher: cacheGraphContentHasher,
                                  cacheGraphLinter: cacheGraphLinter)

        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        artifactBuilder = nil
        cacheGraphContentHasher = nil
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
        cacheGraphContentHasher.contentHashesStub = { _, _ in
            nodeWithHashes
        }
        artifactBuilder.stubbedCacheOutputType = .xcframework

        try subject.cache(path: path, configuration: "Debug")

        // Then
        XCTAssertPrinterOutputContains("""
        Hashing cacheable targets
        Building cacheable targets
        All cacheable targets have been cached successfully as xcframeworks
        """)
        XCTAssertEqual(cacheGraphLinter.invokedLintCount, 1)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList.first?.target, aTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList.last?.target, bTarget)
    }
}
