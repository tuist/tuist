import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct FileElementManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func from_outputs_a_warning_when_the_paths_point_to_directories() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "Documentation/README.md",
            "Documentation/USAGE.md",
        ])

        let manifest = ProjectDescription.FileElement.glob(pattern: "Documentation")

        // When
        let model = try await XcodeGraph.FileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem,
            includeFiles: { !FileHandler.shared.isFolder($0) }
        )

        // Then
        let documentationPath = temporaryPath.appending(component: "Documentation").pathString
        TuistTest.expectLogs(
            "'\(documentationPath)' is a directory, try using: '\(documentationPath)/**' to list its files"
        )
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory) func from_with_hidden_files() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let files = try await TuistTest.createFiles([
            "Additional/.hidden.yml",
        ])

        let manifest = ProjectDescription.FileElement.glob(pattern: "**/.*.yml")

        // When
        let got = try await XcodeGraph.FileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem,
            includeFiles: { !FileHandler.shared.isFolder($0) }
        )

        // Then
        #expect(got.map(\.path) == files)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func from_outputs_a_warning_when_the_folder_reference_is_invalid() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "README.md",
        ])

        let manifest = ProjectDescription.FileElement.folderReference(path: "README.md")

        // When
        let model = try await XcodeGraph.FileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        TuistTest.expectLogs(
            "README.md is not a directory - folder reference paths need to point to directories"
        )
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func fileElement_warning_withMissingFolderReference() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let manifest = ProjectDescription.FileElement.folderReference(path: "Documentation")

        // When
        let model = try await XcodeGraph.FileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        TuistTest.expectLogs("Documentation does not exist")
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory) func from_outputs_empty_when_the_glob_is_invalid() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let manifest = ProjectDescription.FileElement.glob(pattern: "invalid/path/**/*")

        // When
        let got = try await XcodeGraph.FileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(got.isEmpty)
    }

    @Test(.inTemporaryDirectory) func from_excludes_files_matching_excluding_pattern() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let allFiles = try await TuistTest.createFiles([
            "Documentation/README.md",
            "Documentation/USAGE.md",
            "Documentation/internal/SECRET.md",
        ])

        let manifest = ProjectDescription.FileElement.glob(
            pattern: "Documentation/**/*.md",
            excluding: ["Documentation/internal/**"]
        )

        // When
        let got = try await XcodeGraph.FileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem,
            includeFiles: { !FileHandler.shared.isFolder($0) }
        )

        // Then
        let expectedFiles = allFiles.filter { !$0.pathString.contains("internal") }
        #expect(got.map(\.path).sorted() == expectedFiles.sorted())
    }
}
