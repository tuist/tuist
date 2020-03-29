import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class GraphContentHasherTests: TuistUnitTestCase {
    private var sut: GraphContentHasher!

    override func setUp() {
        super.setUp()
        sut = GraphContentHasher()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func test_contentHashes_emptyGraph() throws {
        let graph = Graph.test()
        let hashes = try sut.contentHashes(for: graph)
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let frameworkTarget = TargetNode.test(project: .test(path: path), target: .test(name: "FrameworkA", product: .framework))
        let secondFrameworkTarget = TargetNode.test(project: .test(path: path), target: .test(name: "FrameworkB", product: .framework))
        let appTarget = TargetNode.test(project: .test(path: path), target: .test(name: "App", product: .app))
        let dynamicLibraryTarget = TargetNode.test(project: .test(path: path), target: .test(name: "DynamicLibrary", product: .dynamicLibrary))
        let staticFrameworkTarget = TargetNode.test(project: .test(path: path), target: .test(name: "StaticFramework", product: .staticFramework))

        let graph = Graph.test(entryPath: path,
                               entryNodes: [],
                               projects: [],
                               cocoapods: [],
                               packages: [],
                               precompiled: [],
                               targets: [path: [frameworkTarget, secondFrameworkTarget, appTarget, dynamicLibraryTarget, staticFrameworkTarget]])

        let expectedCachableTargets = [frameworkTarget, secondFrameworkTarget].sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try sut.contentHashes(for: graph)
        let hashedTargets: [TargetNode] = hashes.keys.sorted { left, right -> Bool in
            left.project.path.pathString < right.project.path.pathString
        }.sorted(by: { $0.target.name < $1.target.name })

        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
