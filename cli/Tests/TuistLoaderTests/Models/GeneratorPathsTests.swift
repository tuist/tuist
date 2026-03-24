import FileSystem
import FileSystemTesting
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

struct GeneratorPathsTests {
    private let path: AbsolutePath
    private let subject: GeneratorPaths

    init() throws {
        path = try #require(FileSystem.temporaryTestDirectory)
        subject = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: path.appending(component: "Root")
        )
    }

    @Test(.inTemporaryDirectory) func resolve_when_relative_to_current_file() throws {
        // Given
        let filePath = Path(
            "file.swift",
            type: .relativeToCurrentFile,
            callerPath: path.pathString
        )

        // When
        let got = try subject.resolve(path: filePath)

        // Then
        #expect(got == path.removingLastComponent().appending(component: "file.swift"))
    }

    @Test(.inTemporaryDirectory) func resolve_when_relative_to_manifest() throws {
        // Given
        let filePath = Path.relativeToManifest("file.swift")

        // When
        let got = try subject.resolve(path: filePath)

        // Then
        #expect(got == path.appending(component: "file.swift"))
    }

    @Test(.inTemporaryDirectory) func resolve_when_relative_to_root_directory() throws {
        // Given
        let filePath = Path.relativeToRoot("file.swift")

        // When
        let got = try subject.resolve(path: filePath)

        // Then
        #expect(got == path.appending(component: "Root").appending(component: "file.swift"))
    }
}
