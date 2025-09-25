import Testing
import TuistCore
import XcodeGraph

@testable import TuistCacheEE
@testable import TuistTesting

struct CacheWarmGraphLinterTests {
    var subject: CacheWarmGraphLinter = .init()

    @Test(.withMockedLogger()) func lint_when_scripts_with_side_effects() async throws {
        // Given
        let target = Target.test(scripts: [
            .init(name: "test", order: .post, script: .embedded("echo 'Hello World'")),
        ])
        let project = Project.test(targets: [target])
        let graph = Graph.test(
            projects: [project.path: project]
        )

        // When
        try subject.lint(graph: graph)

        // Then
        TuistTest.expectLogs(
            "The following targets contain scripts that might introduce non-cacheable side-effects"
        )
    }
}
