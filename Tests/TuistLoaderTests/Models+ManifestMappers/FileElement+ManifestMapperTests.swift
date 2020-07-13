import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class FileElementManifestMapperTests: TuistUnitTestCase {
    func test_from_outputs_a_warning_when_the_paths_point_to_directories() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Documentation/README.md",
            "Documentation/USAGE.md",
        ])

        let manifest = ProjectDescription.FileElement.glob(pattern: "Documentation")

        // When
        let model = try TuistCore.FileElement.from(manifest: manifest,
                                                   generatorPaths: generatorPaths,
                                                   includeFiles: { !FileHandler.shared.isFolder($0) })

        // Then
        let documentationPath = temporaryPath.appending(component: "Documentation").pathString
        XCTAssertPrinterOutputContains("'\(documentationPath)' is a directory, try using: '\(documentationPath)/**' to list its files")
        XCTAssertEqual(model, [])
    }

    func test_from_when_the_path_points_to_nonexisting_file() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.FileElement.glob(pattern: "Documentation/**")

        // When
        let model = try TuistCore.FileElement.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        let documentationPath = temporaryPath.appending(RelativePath("Documentation/**"))
        XCTAssertPrinterOutputContains("No files found at: \(documentationPath)")
        XCTAssertEqual(model, [])
    }

    func test_from_outputs_a_warning_when_the_folder_reference_is_invalid() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "README.md",
        ])

        let manifest = ProjectDescription.FileElement.folderReference(path: "README.md")

        // When
        let model = try TuistCore.FileElement.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertPrinterOutputContains("README.md is not a directory - folder reference paths need to point to directories")
        XCTAssertEqual(model, [])
    }

    func test_fileElement_warning_withMissingFolderReference() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.FileElement.folderReference(path: "Documentation")

        // When
        let model = try TuistCore.FileElement.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertPrinterOutputContains("Documentation does not exist")
        XCTAssertEqual(model, [])
    }

    func test_throws_when_the_glob_is_invalid() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.FileElement.glob(pattern: "invalid/path/**/*")
        let invalidGlob = InvalidGlob(pattern: temporaryPath.appending(RelativePath("invalid/path/**/*")).pathString,
                                      nonExistentPath: temporaryPath.appending(RelativePath("invalid/path/")))
        let error = GlobError.nonExistentDirectory(invalidGlob)

        // Then
        XCTAssertThrowsSpecific(try TuistCore.FileElement.from(manifest: manifest, generatorPaths: generatorPaths), error)
    }
}
