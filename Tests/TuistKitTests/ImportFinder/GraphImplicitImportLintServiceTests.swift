import FileSystem
import Path
import TuistCore
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class GraphImplicitImportLintServiceTests: TuistUnitTestCase {
    func test_targetLintWithImports() async throws {
        // Given
        let fileSystem = FileSystem()
        let path = try temporaryPath()
        let targetPath = path
            .appending(components: "FirstTarget", "Sources")
        let filePath = targetPath.appending(
            component: "File.swift"
        )

        try await fileSystem.makeDirectory(at: targetPath)

        try await fileSystem.writeText(
            """
            import ExplicitTarget
            import ImplicitTarget
            import Foundation

            let a = 5
            """,
            at: filePath
        )

        let firstTarget = Target.test(
            name: "FirstTarget",
            sources: [
                SourceFile(path: filePath),
            ],
            dependencies: [
                TargetDependency.target(name: "ExplicitTarget", condition: nil),
            ]
        )

        let project = Project.test(
            name: "FirstProject",
            targets: [
                firstTarget,
                Target.test(
                    name: "ExplicitTarget"
                ),
                Target.test(
                    name: "ImplicitTarget"
                ),
            ]
        )
        let graph = Graph.test(projects: [
            path: project,
        ])

        // When
        let result = try await GraphImplicitImportLintService()
            .lint(graphTraverser: GraphTraverser(graph: graph), config: Config.test())

        // Then
        XCTAssertEqual(
            result,
            [LintingIssue(reason: "Target FirstTarget implicitly imports ImplicitTarget.", severity: .warning)]
        )
    }
}
