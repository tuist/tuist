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

struct CopyFileElementManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func from_outputs_a_warning_when_the_paths_point_to_directories() async throws {
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

        let manifest = ProjectDescription.CopyFileElement.glob(pattern: "Documentation")

        // When
        let model = try await XcodeGraph.CopyFileElement.from(
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

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func from_outputs_a_warning_when_the_folder_reference_is_invalid() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "README.md",
        ])

        let manifest = ProjectDescription.CopyFileElement.folderReference(path: "README.md")

        // When
        let model = try await XcodeGraph.CopyFileElement.from(
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

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func copyFileElement_warning_withMissingFolderReference() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let manifest = ProjectDescription.CopyFileElement.folderReference(path: "Documentation")

        // When
        let model = try await XcodeGraph.CopyFileElement.from(
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
        let manifest = ProjectDescription.CopyFileElement.glob(pattern: "invalid/path/**/*")

        // When
        let got = try await XcodeGraph.CopyFileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(got.isEmpty)
    }
}
