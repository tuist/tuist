import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class CopyFileElementManifestMapperTests: TuistUnitTestCase {
    func test_from_outputs_a_warning_when_the_paths_point_to_directories() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
            let rootDirectory = temporaryPath
            let generatorPaths = GeneratorPaths(
                manifestDirectory: temporaryPath,
                rootDirectory: rootDirectory
            )
            try await createFiles([
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
            XCTAssertPrinterOutputContains(
                "'\(documentationPath)' is a directory, try using: '\(documentationPath)/**' to list its files"
            )
            XCTAssertEqual(model, [])
        }
    }

    func test_from_outputs_a_warning_when_the_folder_reference_is_invalid() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
            let rootDirectory = temporaryPath
            let generatorPaths = GeneratorPaths(
                manifestDirectory: temporaryPath,
                rootDirectory: rootDirectory
            )
            try await createFiles([
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
            XCTAssertPrinterOutputContains(
                "README.md is not a directory - folder reference paths need to point to directories"
            )
            XCTAssertEqual(model, [])
        }
    }

    func test_copyFileElement_warning_withMissingFolderReference() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryPath = try temporaryPath()
            let rootDirectory = temporaryPath
            let generatorPaths = GeneratorPaths(
                manifestDirectory: temporaryPath,
                rootDirectory: rootDirectory
            )
            let manifest = ProjectDescription.CopyFileElement.folderReference(path: "Documentation")

            // When
            let model = try await XcodeGraph.CopyFileElement.from(
                manifest: manifest,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )

            // Then
            XCTAssertPrinterOutputContains("Documentation does not exist")
            XCTAssertEqual(model, [])
        }
    }

    func test_from_outputs_empty_when_the_glob_is_invalid() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        let manifest = ProjectDescription.CopyFileElement.glob(pattern: "invalid/path/**/*")

        // When
        let got = try await XcodeGraph.CopyFileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEmpty(got)
    }
}
