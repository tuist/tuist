import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class TestsGraphContentHasherTests: TuistUnitTestCase {
    private var subject: TestsGraphContentHasher!

    override func setUp() {
        super.setUp()
        subject = TestsGraphContentHasher(
            targetContentHasher: TargetContentHasher(
                contentHasher: ContentHasher()
            )
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_contentHashes_emptyGraph() throws {
        // Given
        let graph = Graph.test()

        // When
        let hashes = try subject.contentHashes(
            graph: graph
        )

        // Then
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyUnitTestsAndItsDependencies() throws {
        // Given
        let path: AbsolutePath = "/project"
        let project = Project.test(
            path: path
        )
        let frameworkD = TargetNode.test(
            project: project,
            target: .test(
                name: "FrameworkD",
                product: .framework
            )
        )
        let frameworkA = TargetNode.test(
            project: project,
            target: .test(
                name: "FrameworkA",
                product: .framework
            ),
            dependencies: [
                frameworkD,
            ]
        )
        let frameworkB = TargetNode.test(
            project: project,
            target: .test(
                name: "FrameworkB",
                product: .framework
            )
        )
        let frameworkC = TargetNode.test(
            project: project,
            target: .test(
                name: "FrameworkC",
                product: .framework
            )
        )
        let unitTestsA = TargetNode.test(
            project: project,
            target: .test(
                name: "UnitTestsA",
                product: .unitTests
            ),
            dependencies: [
                frameworkA,
            ]
        )
        let unitTestsB = TargetNode.test(
            project: project,
            target: .test(
                name: "UnitTestsB",
                product: .unitTests
            ),
            dependencies: [
                frameworkD,
            ]
        )
        let uiTests = TargetNode.test(
            project: project,
            target: .test(
                name: "UITests",
                product: .uiTests
            ),
            dependencies: [
                frameworkB,
            ]
        )

        let graph = Graph.test(
            projects: [
                project,
            ],
            targets: [
                path: [
                    frameworkA,
                    frameworkB,
                    frameworkC,
                    frameworkD,
                    unitTestsA,
                    unitTestsB,
                    uiTests,
                ],
            ]
        )
        let expectedCachableTargets = [
            frameworkA,
            frameworkD,
            unitTestsA,
            unitTestsB,
        ]
        .sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try subject.contentHashes(graph: graph)
        let hashedTargets: [TargetNode] = hashes.keys
            .sorted { left, right -> Bool in
                left.project.path.pathString < right.project.path.pathString
            }
            .sorted(by: { $0.target.name < $1.target.name })

        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
