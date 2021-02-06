import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import XCTest
import TuistGraph

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
        let graph = ValueGraph.test()
        let graphTraverser = ValueGraphTraverser(graph: graph)

        // When
        let hashes = try subject.contentHashes(
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyUnitTestsAndItsDependencies() throws {
        // Given
        let path: AbsolutePath = "/project"
        let frameworkA = ValueGraphTarget.test(
            path: path,
            target: .test(
                name: "FrameworkA",
                product: .framework
            ),
            project: .test(path: path)
        )
        let frameworkB = ValueGraphTarget.test(
            path: path,
            target: .test(
                name: "FrameworkB",
                product: .framework
            ),
            project: .test(path: path)
        )
        let frameworkC = ValueGraphTarget.test(
            path: path,
            target: .test(
                name: "FrameworkC",
                product: .framework
            ),
            project: .test(path: path)
        )
        let frameworkD = ValueGraphTarget.test(
            path: path,
            target: .test(
                name: "FrameworkD",
                product: .framework
            ),
            project: .test(path: path)
        )
        let unitTests = ValueGraphTarget.test(
            path: path,
            target: .test(
                name: "UnitTests",
                product: .unitTests
            ),
            project: .test(path: path)
        )
        let uiTests = ValueGraphTarget.test(
            path: path,
            target: .test(
                name: "UITests",
                product: .uiTests
            ),
            project: .test(path: path)
        )
        let project = Project.test(
            path: path
        )
        let graph = ValueGraph.test(
            path: path,
            projects: [
                path: project
            ],
            targets: [
                path: [
                    frameworkA.target.name: frameworkA.target,
                    frameworkB.target.name: frameworkB.target,
                    frameworkC.target.name: frameworkC.target,
                    frameworkD.target.name: frameworkD.target,
                    unitTests.target.name: unitTests.target,
                    uiTests.target.name: uiTests.target,
                ]
            ],
            dependencies: [
                .target(
                    name: unitTests.target.name,
                    path: unitTests.path
                ): Set([
                    .target(
                        name: frameworkA.target.name,
                        path: frameworkA.path
                    )
                ]),
                .target(
                    name: frameworkA.target.name,
                    path: frameworkA.path
                ): Set([
                    .target(
                        name: frameworkD.target.name,
                        path: frameworkD.path
                    )
                ]),
                .target(
                    name: uiTests.target.name,
                    path: uiTests.path
                ): Set([
                    .target(
                        name: frameworkB.target.name,
                        path: frameworkB.path
                    )
                ]),
            ]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let expectedCachableTargets = [
            frameworkA,
            frameworkD,
            unitTests,
        ]
        .sorted(by: { $0.target.name < $1.target.name })

        // When
        let hashes = try subject.contentHashes(graphTraverser: graphTraverser)
        let hashedTargets: [ValueGraphTarget] = hashes.keys
            .sorted { left, right -> Bool in
                left.project.path.pathString < right.project.path.pathString
            }
            .sorted(by: { $0.target.name < $1.target.name })

        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
