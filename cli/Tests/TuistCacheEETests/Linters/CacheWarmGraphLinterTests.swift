import Logging
import Path
import Testing
import TuistCore
import TuistLoggerTesting
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

    @Test(.withMockedLogger()) func lint_does_not_warn_for_scripts_with_defined_inputs_and_outputs() async throws {
        // Given
        let target = Target.test(scripts: [
            .init(
                name: "test",
                order: .post,
                script: .embedded("echo 'Hello World'"),
                inputPaths: ["/input"],
                outputPaths: ["/output"]
            ),
        ])
        let project = Project.test(targets: [target])
        let graph = Graph.test(
            projects: [project.path: project]
        )

        // When
        try subject.lint(graph: graph)

        // Then
        let output = Logger.testingLogHandler.collected[.warning, >=]
        #expect(!output.contains("non-cacheable side-effects"))
    }

    @Test(.withMockedLogger()) func lint_does_not_warn_for_aggregate_targets() async throws {
        // Given
        let target = Target.test(
            scripts: [
                .init(name: "Foreign Build", order: .pre, script: .embedded("gradle build")),
            ],
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: try AbsolutePath(validating: "/output.xcframework"), linking: .dynamic)
            )
        )
        let project = Project.test(targets: [target])
        let graph = Graph.test(
            projects: [project.path: project]
        )

        // When
        try subject.lint(graph: graph)

        // Then
        let output = Logger.testingLogHandler.collected[.warning, >=]
        #expect(!output.contains("non-cacheable side-effects"))
    }
}
