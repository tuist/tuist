import FileSystem
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class TargetImportsScannerTests: TuistUnitTestCase {
    func test_scannerTargetWithImports() async throws {
        // Given
        let fileSystem = FileSystem()
        let path = try temporaryPath()
        let targetPath = path.appending(components: "FirstTarget", "Sources")

        let targetFirstFile = targetPath.appending(component: "FirstFile.swift")
        let targetSecondFile = targetPath.appending(component: "SecondFile.swift")

        try await fileSystem.makeDirectory(at: targetPath)

        try await fileSystem.writeText(
            """
            import SecondTarget
            import A

            let a = 5
            """,
            at: targetFirstFile
        )

        try await fileSystem.writeText(
            """
            @testable import ThirdTarget

            func main() { }
            """,
            at: targetSecondFile
        )

        let target = Target.test(
            name: "FirstTarget",
            sources: [
                SourceFile(path: targetFirstFile),
                SourceFile(path: targetSecondFile),
            ]
        )

        // When
        let result = try await TargetImportsScanner()
            .imports(for: target)

        // Then
        XCTAssertEqual(result, ["SecondTarget", "ThirdTarget", "A"])
    }
}
