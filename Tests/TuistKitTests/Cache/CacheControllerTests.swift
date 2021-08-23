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
    var bundleArtifactBuilder: MockCacheArtifactBuilder!
    var manifestLoader: MockManifestLoader!
    var cache: MockCacheStorage!
    var subject: CacheController!
    var projectGeneratorProvider: MockCacheControllerProjectGeneratorProvider!
    var config: Config!
    var cacheGraphLinter: MockCacheGraphLinter!

    override func setUp() {
        generator = MockGenerator()
        artifactBuilder = MockCacheArtifactBuilder()
        bundleArtifactBuilder = MockCacheArtifactBuilder()
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
            bundleArtifactBuilder: bundleArtifactBuilder,
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
        bundleArtifactBuilder = nil
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

        let aGraphTarget = GraphTarget.test(path: project.path, target: aTarget, project: project)
        let bGraphTarget = GraphTarget.test(path: project.path, target: bTarget, project: project)
        let cGraphTarget = GraphTarget.test(path: project.path, target: cTarget, project: project)
        let nodeWithHashes = [
            aGraphTarget: "\(aTarget.name)_HASH",
            bGraphTarget: "\(bTarget.name)_HASH",
            cGraphTarget: "\(cTarget.name)_HASH",
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: nodeWithHashes.keys.reduce(into: [project.path: [String: Target]()]) { $0[project.path]?[$1.target.name] = $1.target },
            dependencies: [
                .target(name: bGraphTarget.target.name, path: bGraphTarget.path): [
                    .target(name: aGraphTarget.target.name, path: aGraphTarget.path),
                ],
                .target(name: cGraphTarget.target.name, path: cGraphTarget.path): [
                    .target(name: bGraphTarget.target.name, path: bGraphTarget.path),
                ],
            ]
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
        try subject.cache(path: path, cacheProfile: .test(configuration: "Debug"), targetsToFilter: [], dependenciesOnly: false)

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
        XCTAssertEqual(artifactBuilder.invokedBuildProjectTargetParametersList[0].target, aTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildProjectTargetParametersList[1].target, bTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildProjectTargetParametersList[2].target, cTarget)
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

        let aGraphTarget = GraphTarget.test(path: project.path, target: aTarget, project: project)
        let bGraphTarget = GraphTarget.test(path: project.path, target: bTarget, project: project)
        let cGraphTarget = GraphTarget.test(path: project.path, target: cTarget, project: project)
        let nodeWithHashes = [
            aGraphTarget: "\(aTarget.name)_HASH",
            bGraphTarget: "\(bTarget.name)_HASH",
            cGraphTarget: "\(cTarget.name)_HASH",
        ]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: nodeWithHashes.keys.reduce(into: [project.path: [String: Target]()]) { $0[project.path]?[$1.target.name] = $1.target },
            dependencies: [
                .target(name: bGraphTarget.target.name, path: bGraphTarget.path): [
                    .target(name: aGraphTarget.target.name, path: aGraphTarget.path),
                ],
                .target(name: cGraphTarget.target.name, path: cGraphTarget.path): [
                    .target(name: bGraphTarget.target.name, path: bGraphTarget.path),
                ],
            ]
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
        try subject.cache(path: path, cacheProfile: .test(configuration: "Debug"), targetsToFilter: [bTarget.name], dependenciesOnly: false)

        // Then
        XCTAssertPrinterOutputContains("""
        Hashing cacheable targets
        Building cacheable targets
        Building cacheable targets: \(aTarget.name), 1 out of 2
        Building cacheable targets: \(bTarget.name), 2 out of 2
        All cacheable targets have been cached successfully as xcframeworks
        """)
        XCTAssertEqual(cacheGraphLinter.invokedLintCount, 1)
        XCTAssertEqual(artifactBuilder.invokedBuildProjectTargetParametersList[0].target, aTarget)
        XCTAssertEqual(artifactBuilder.invokedBuildProjectTargetParametersList[1].target, bTarget)
    }

    func test_filtered_cache_builds_with_dependencies_only_and_caches_the_frameworks() throws {
        // Given
        let project = Project.test()
        let aTarget = Target.test(name: "a")
        let bTarget = Target.test(name: "b")
        let cTarget = Target.test(name: "c")
        let aGraphTarget = GraphTarget.test(path: project.path, target: aTarget, project: project)
        let bGraphTarget = GraphTarget.test(path: project.path, target: bTarget, project: project)
        let cGraphTarget = GraphTarget.test(path: project.path, target: cTarget, project: project)
        let graphTargets = [aGraphTarget, bGraphTarget, cGraphTarget]
        let graph = Graph.test(
            projects: [project.path: project],
            targets: graphTargets.reduce(into: [project.path: [String: Target]()]) { $0[project.path]?[$1.target.name] = $1.target },
            dependencies: [
                // `bTarget` is a dependency of `aTarget`.
                .target(name: aGraphTarget.target.name, path: aGraphTarget.path): [
                    .target(name: bGraphTarget.target.name, path: bGraphTarget.path),
                ],
                // `cTarget` is a dependency of `bTarget`.
                .target(name: bGraphTarget.target.name, path: bGraphTarget.path): [
                    .target(name: cGraphTarget.target.name, path: cGraphTarget.path),
                ],
            ]
        )

        let nodeWithHashes = [
            aGraphTarget: "\(aTarget.name)_HASH",
            bGraphTarget: "\(bTarget.name)_HASH",
            cGraphTarget: "\(cTarget.name)_HASH",
        ]
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in nodeWithHashes }

        artifactBuilder.stubbedCacheOutputType = .xcframework

        // When
        let results = try subject.makeHashesByTargetToBeCached(
            for: graph,
            cacheProfile: .test(),
            targetsToFilter: [aTarget.name, bTarget.name],
            dependenciesOnly: true
        )

        // Then
        XCTAssertEqual(results.count, 1)
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.0, cGraphTarget)
        XCTAssertEqual(first.1, nodeWithHashes[cGraphTarget])
    }

    func test_given_target_to_filter_is_not_cacheable_should_cache_its_depedendencies() throws {
        // Given
        let project = Project.test()
        let aTarget = Target.test(name: "a")
        let bTarget = Target.test(name: "b")
        let aGraphTarget = GraphTarget.test(path: project.path, target: aTarget, project: project)
        let bGraphTarget = GraphTarget.test(path: project.path, target: bTarget, project: project)
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [aGraphTarget, bGraphTarget].reduce(into: [project.path: [String: Target]()]) { $0[project.path]?[$1.target.name] = $1.target },
            dependencies: [
                // `bTarget` is a dependency of `aTarget`.
                .target(name: aGraphTarget.target.name, path: aGraphTarget.path): [
                    .target(name: bGraphTarget.target.name, path: bGraphTarget.path),
                ],
            ]
        )

        // `aTarget` is not cacheable, but `bTarget` (its dependency) it is.
        let nodeWithHashes = [
            bGraphTarget: "\(bTarget.name)_HASH",
        ]
        cacheGraphContentHasher.contentHashesStub = { _, _, _ in
            nodeWithHashes
        }

        artifactBuilder.stubbedCacheOutputType = .xcframework

        // When
        let results = try subject.makeHashesByTargetToBeCached(for: graph, cacheProfile: .test(), targetsToFilter: [aTarget.name], dependenciesOnly: false)

        // Then
        XCTAssertEqual(results.count, 1)
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.0, bGraphTarget)
        XCTAssertEqual(first.1, nodeWithHashes[bGraphTarget])
    }
}
