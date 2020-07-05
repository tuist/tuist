import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class GraphContentHasherTests: TuistUnitTestCase {
    private var subject: GraphContentHasher!

    override func setUp() {
        super.setUp()
        subject = GraphContentHasher()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_contentHashes_emptyGraph() throws {
        // Given
        let graph = Graph.test()

        // When
        let hashes = try subject.contentHashes(for: graph)

        // Then
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let frameworkTarget = TargetNode.test(project: .test(path: path), target: .test(name: "FrameworkA", product: .framework, infoPlist: nil, entitlements: nil))
        let secondFrameworkTarget = TargetNode.test(project: .test(path: path), target: .test(name: "FrameworkB", product: .framework, infoPlist: nil, entitlements: nil))
        let appTarget = TargetNode.test(project: .test(path: path), target: .test(name: "App", product: .app, infoPlist: nil, entitlements: nil))
        let dynamicLibraryTarget = TargetNode.test(project: .test(path: path), target: .test(name: "DynamicLibrary", product: .dynamicLibrary, infoPlist: nil, entitlements: nil))
        let staticFrameworkTarget = TargetNode.test(project: .test(path: path), target: .test(name: "StaticFramework", product: .staticFramework, infoPlist: nil, entitlements: nil))

        let graph = Graph.test(entryPath: path,
                               entryNodes: [],
                               projects: [],
                               cocoapods: [],
                               packages: [],
                               precompiled: [],
                               targets: [path: [frameworkTarget, secondFrameworkTarget, appTarget, dynamicLibraryTarget, staticFrameworkTarget]])

        let expectedCachableTargets = [frameworkTarget, secondFrameworkTarget].sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try subject.contentHashes(for: graph)
        let hashedTargets: [TargetNode] = hashes.keys.sorted { left, right -> Bool in
            left.project.path.pathString < right.project.path.pathString
        }.sorted(by: { $0.target.name < $1.target.name })

        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
