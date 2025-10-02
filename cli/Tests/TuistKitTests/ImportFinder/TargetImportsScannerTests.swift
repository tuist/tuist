import FileSystem
import Foundation
import Testing
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistKit

struct TargetImportsScannerTests {
    private let fileSystem = FileSystem()

    @Test func imports() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let targetPath = temporaryDirectory.appending(components: "FirstTarget", "Sources")

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
            #expect(result == ["SecondTarget", "ThirdTarget", "A"])
        }
    }

    @Test func imports_in_buildable_folder_sources() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let targetPath = temporaryDirectory.appending(components: "FirstTarget", "Sources")

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
                buildableFolders: [
                    BuildableFolder(
                        path: "/Sources",
                        exceptions: [],
                        resolvedFiles: [
                            BuildableFolderFile(path: targetFirstFile, compilerFlags: nil),
                            BuildableFolderFile(path: targetSecondFile, compilerFlags: nil),
                        ]
                    ),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == ["SecondTarget", "ThirdTarget", "A"])
        }
    }

    @Test func imports_when_filesAreAbsent() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let sourcesPath = temporaryDirectory.appending(components: "Target", "Sources")
            let sourcePath = sourcesPath.appending(component: "Source.swift")
            let target = Target.test(
                name: "Target",
                sources: [
                    SourceFile(path: sourcePath),
                ]
            )

            // When
            let result = try await TargetImportsScanner()
                .imports(for: target)

            // Then
            #expect(result == [])
        }
    }
}
