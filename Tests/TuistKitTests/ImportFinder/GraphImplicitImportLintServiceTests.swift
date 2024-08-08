import Path
import TuistCore
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class GraphImplicitImportLintServiceTests: TuistUnitTestCase {
    func test_TargetLintWithImports() async throws {
        let path = try temporaryPath()
        let firstTargetPath = path.appending(try RelativePath(validating: "FirstTarget"))

        let firstTargetFile = firstTargetPath.appending(component: "Sources").appending(component: "File.swift")
        try FileHandler.shared.createFolder(firstTargetPath)

        try FileHandler.shared.touch(firstTargetFile)
        try FileHandler.shared.write(
            """
            import ExplicitTarget
            import ImplicitTarget
            import Foundation

            let a = 5
            """,
            path: firstTargetFile,
            atomically: false
        )

        let firstTarget = Target.test(
            name: "FirstTarget",
            sources: [
                SourceFile(path: firstTargetFile),
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
        let result = try await GraphImplicitImportLintService(
            importSourceCodeScanner: ImportSourceCodeScanner()
        ).lint(graph: GraphTraverser(graph: graph), config: Config.test())
        XCTAssertEqual(
            result,
            [LintingIssue(reason: "Target FirstTarget implicitly imports ImplicitTarget.", severity: .warning)]
        )
    }

    func test_TargetHandleWithImports() async throws {
        let path = try temporaryPath()
        let targetPath = path.appending(try RelativePath(validating: "FirstTarget"))

        let targetFirstFile = targetPath.appending(component: "Sources").appending(component: "FirstFile.swift")
        let targetSecondFile = targetPath.appending(component: "Sources").appending(component: "SecondFile.swift")

        try FileHandler.shared.createFolder(targetPath)

        try FileHandler.shared.touch(targetFirstFile)
        try FileHandler.shared.touch(targetSecondFile)

        try FileHandler.shared.write(
            """
            import SecondTarget
            import A

            let a = 5
            """,
            path: targetFirstFile,
            atomically: false
        )

        try FileHandler.shared.write(
            """
            @testable import ThirdTarget

            func main() { }
            """,
            path: targetSecondFile,
            atomically: false
        )

        let target = Target.test(
            name: "FirstTarget",
            sources: [
                SourceFile(path: targetFirstFile),
                SourceFile(path: targetSecondFile),
            ]
        )
        let result = try await GraphImplicitImportLintService(
            importSourceCodeScanner: ImportSourceCodeScanner()
        ).imports(for: target)
        XCTAssertEqual(result, ["SecondTarget", "ThirdTarget", "A"])
    }
}
