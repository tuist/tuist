import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

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
        let hashes = try subject.contentHashes(for: graph)

        // Then
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let project: Project = .test(
            path: path
        )
        let frameworkTarget = GraphTarget.test(
            path: path,
            target: .test(
                name: "FrameworkA",
                product: .framework,
                infoPlist: nil,
                entitlements: nil
            ),
            project: .test(path: path)
        )
        let secondFrameworkTarget = GraphTarget.test(
            path: path,
            target: .test(
                name: "FrameworkB",
                product: .framework,
                infoPlist: nil,
                entitlements: nil
            ),
            project: .test(path: path)
        )
        let appTarget = GraphTarget.test(
            path: path,
            target: .test(
                name: "App",
                product: .app,
                infoPlist: nil,
                entitlements: nil
            ),
            project: .test(path: path)
        )
        let dynamicLibraryTarget = GraphTarget.test(
            path: path,
            target: .test(
                name: "DynamicLibrary",
                product: .dynamicLibrary,
                infoPlist: nil,
                entitlements: nil
            ),
            project: .test(path: path)
        )
        let staticFrameworkTarget = GraphTarget.test(
            path: path,
            target: .test(
                name: "StaticFramework",
                product: .staticFramework,
                infoPlist: nil,
                entitlements: nil
            ),
            project: .test(path: path)
        )

        let graph = Graph.test(
            path: path,
            projects: [project.path: project],
            targets: [
                path: [
                    frameworkTarget.target.name: frameworkTarget.target,
                    secondFrameworkTarget.target.name: secondFrameworkTarget.target,
                    appTarget.target.name: appTarget.target,
                    dynamicLibraryTarget.target.name: dynamicLibraryTarget.target,
                    staticFrameworkTarget.target.name: staticFrameworkTarget.target,
                ],
            ]
        )

        let expectedCachableTargets = [frameworkTarget, secondFrameworkTarget].sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try subject.contentHashes(
            for: graph,
            filter: {
                $0.target.product == .framework
            }
        )
        let hashedTargets: [GraphTarget] = hashes.keys.sorted { left, right -> Bool in
            left.path.pathString < right.path.pathString
        }
        .sorted(by: { $0.target.name < $1.target.name })

        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
