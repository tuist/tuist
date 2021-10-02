import TuistCore
import TuistGraph
import XCTest
@testable import TuistCache
@testable import TuistCoreTesting
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class CacheGraphLinterTests: TuistUnitTestCase {
    var subject: CacheGraphLinter!

    override func setUp() {
        super.setUp()
        subject = CacheGraphLinter()
    }

    func test_lint() {
        // Given
        let project = Project.test()
        let target = Target.test(scripts: [
            .init(name: "test", order: .post, script: .embedded("echo 'Hello World'")),
        ])
        let graphTarget = GraphTarget.test(
            path: project.path,
            target: target,
            project: project
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                graphTarget.path: [graphTarget.target.name: graphTarget.target],
            ]
        )

        // When
        subject.lint(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("""
        The following targets contain scripts that might introduce non-cacheable side-effects
        """)
    }
}
