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
        let target = Target.test(actions: [
            .init(name: "test", order: .post, script: .embedded("echo 'Hello World'")),
        ])
        let targetNode = TargetNode.test(target: target)
        let graph = Graph.test(entryNodes: [targetNode],
                               targets: [targetNode.path: [targetNode]])

        // When
        subject.lint(graph: graph)

        // Then
        XCTAssertPrinterOutputContains("""
        The following targets contain actions that might introduce non-cacheable side-effects
        """)
    }
}
