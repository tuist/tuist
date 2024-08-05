import Foundation
import Path
import TuistCore
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class GraphContentHasherTests: TuistUnitTestCase {
    private var subject: GraphContentHasher!

    override func setUp() {
        super.setUp()
        subject = GraphContentHasher(contentHasher: ContentHasher())
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_contentHashes_emptyGraph() throws {
        // Given
        let graph = Graph.test()

        // When
        let hashes = try subject.contentHashes(for: graph, include: { _ in true }, additionalStrings: [])

        // Then
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let frameworkATarget: Target = .test(
            name: "FrameworkA",
            product: .framework,
            infoPlist: nil,
            entitlements: nil
        )
        let frameworkBTarget: Target = .test(
            name: "FrameworkB",
            product: .framework,
            infoPlist: nil,
            entitlements: nil
        )
        let appTarget: Target = .test(
            name: "App",
            product: .app,
            infoPlist: nil,
            entitlements: nil
        )
        let dynamicLibraryTarget: Target = .test(
            name: "DynamicLibrary",
            product: .dynamicLibrary,
            infoPlist: nil,
            entitlements: nil
        )
        let staticFrameworkTarget: Target = .test(
            name: "StaticFramework",
            product: .staticFramework,
            infoPlist: nil,
            entitlements: nil
        )

        let project: Project = .test(
            path: path,
            targets: [frameworkATarget, frameworkBTarget, appTarget, dynamicLibraryTarget, staticFrameworkTarget]
        )
        let frameworkTarget = GraphTarget.test(
            path: path,
            target: frameworkATarget,
            project: project
        )
        let secondFrameworkTarget = GraphTarget.test(
            path: path,
            target: frameworkBTarget,
            project: project
        )
        let graph = Graph.test(
            path: path,
            projects: [project.path: project]
        )

        let expectedCachableTargets = [frameworkTarget, secondFrameworkTarget].sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try subject.contentHashes(
            for: graph,
            include: {
                $0.target.product == .framework
            },
            additionalStrings: []
        )
        let hashedTargets: [GraphTarget] = hashes.keys.sorted { left, right -> Bool in
            left.path.pathString < right.path.pathString
        }
        .sorted(by: { $0.target.name < $1.target.name })

        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
