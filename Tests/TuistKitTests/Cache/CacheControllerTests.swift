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
        subject = CacheController(
            cache: cache,
            artifactBuilder: artifactBuilder,
            projectGeneratorProvider: projectGeneratorProvider,
            cacheGraphContentHasher: cacheGraphContentHasher,
            cacheGraphLinter: cacheGraphLinter
        )

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
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let aFrameworkPath = path.appending(component: "\(aTarget.name).framework")
        let bFrameworkPath = path.appending(component: "\(bTarget.name).framework")
        let cFrameworkPath = path.appending(component: "\(cTarget.name).framework")
        try FileHandler.shared.createFolder(aFrameworkPath)
        try FileHandler.shared.createFolder(bFrameworkPath)
        try FileHandler.shared.createFolder(cFrameworkPath)

        let aTargetNode = TargetNode.test(project: project, target: aTarget)
        let bTargetNode = TargetNode.test(project: project, target: bTarget, dependencies: [aTargetNode])
        let cTargetNode = TargetNode.test(project: project, target: cTarget, dependencies: [bTargetNode])
        let nodeWithHashes = [
            aTargetNode: "\(aTarget.name)_HASH",
            bTargetNode: "\(bTarget.name)_HASH",
            cTargetNode: "\(cTarget.name)_HASH",
        ]
        let graph = Graph.test(
            projects: [project],
            targets: nodeWithHashes.keys.reduce(into: [project.path: [TargetNode]()]) { $0[project.path]?.append($1) }
        )

        manifestLoader.manifestsAtStub = { (loadPath: AbsolutePath) -> Set<Manifest> in
            XCTAssertEqual(loadPath, path)
            return Set(arrayLiteral: .project)
        }
        generator.generateWithGraphStub = { (loadPath, _) -> (AbsolutePath, Graph) in
            XCTAssertEqual(loadPath, path)
            return (xcworkspacePath, graph)
        }
        generator.generateStub = { (loadPath, _) -> AbsolutePath in
            XCTAssertEqual(loadPath, path)
            return xcworkspacePath
        }
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in
            nodeWithHashes
        }
        artifactBuilder.stubbedCacheOutputType = .xcframework

        // When
        try subject.cache(path: path, cacheProfile: .test(configuration: "Debug"), targetsToFilter: [])

        // Then
        XCTAssertPrinterOutputContains("""
        Hashing cacheable targets
        Building cacheable targets
        Building cacheable targets: \(aTarget.name), 1 out of 3
        Building cacheable targets: \(bTarget.name), 2 out of 3
        Building cacheable targets: \(cTarget.name), 3 out of 3
        All cacheable targets have been cached successfully as xcframeworks
        """)
        XCTAssertEqual(cacheGraphLinter.invokedLintCount, 1)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList[0].target, aTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList[1].target, bTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList[2].target, cTarget)
    }

    func test_filtered_cache_builds_and_caches_the_frameworks() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let project = Project.test(path: path, name: "Cache")
        let targetNames = ["foo", "bar", "baz"].shuffled()
        let aTarget = Target.test(name: targetNames[0])
        let bTarget = Target.test(name: targetNames[1])
        let cTarget = Target.test(name: targetNames[2])
        let aFrameworkPath = path.appending(component: "\(aTarget.name).framework")
        let bFrameworkPath = path.appending(component: "\(bTarget.name).framework")
        let cFrameworkPath = path.appending(component: "\(cTarget.name).framework")
        try FileHandler.shared.createFolder(aFrameworkPath)
        try FileHandler.shared.createFolder(bFrameworkPath)
        try FileHandler.shared.createFolder(cFrameworkPath)

        let aTargetNode = TargetNode.test(project: project, target: aTarget)
        let bTargetNode = TargetNode.test(project: project, target: bTarget, dependencies: [aTargetNode])
        let cTargetNode = TargetNode.test(project: project, target: cTarget, dependencies: [bTargetNode])
        let nodeWithHashes = [
            aTargetNode: "\(aTarget.name)_HASH",
            bTargetNode: "\(bTarget.name)_HASH",
            cTargetNode: "\(cTarget.name)_HASH",
        ]
        let graph = Graph.test(
            projects: [project],
            targets: nodeWithHashes.keys.reduce(into: [project.path: [TargetNode]()]) { $0[project.path]?.append($1) }
        )

        manifestLoader.manifestsAtStub = { (loadPath: AbsolutePath) -> Set<Manifest> in
            XCTAssertEqual(loadPath, path)
            return Set(arrayLiteral: .project)
        }
        generator.generateWithGraphStub = { (loadPath, _) -> (AbsolutePath, Graph) in
            XCTAssertEqual(loadPath, path)
            return (xcworkspacePath, graph)
        }
        generator.generateStub = { (loadPath, _) -> AbsolutePath in
            XCTAssertEqual(loadPath, path)
            return xcworkspacePath
        }
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in
            nodeWithHashes
        }
        artifactBuilder.stubbedCacheOutputType = .xcframework

        // When
        try subject.cache(path: path, cacheProfile: .test(configuration: "Debug"), targetsToFilter: [bTarget.name])

        // Then
        XCTAssertPrinterOutputContains("""
        Hashing cacheable targets
        Building cacheable targets
        Building cacheable targets: \(aTarget.name), 1 out of 2
        Building cacheable targets: \(bTarget.name), 2 out of 2
        All cacheable targets have been cached successfully as xcframeworks
        """)
        XCTAssertEqual(cacheGraphLinter.invokedLintCount, 1)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList[0].target, aTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildWorkspacePathParametersList[1].target, bTarget)
    }
}
