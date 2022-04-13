import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ResourceFileElementManifestMapperTests: TuistUnitTestCase {
    func test_from_outputs_a_warning_when_the_paths_point_to_directories() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Documentation/README.md",
            "Documentation/USAGE.md",
        ])

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Documentation")

        // When
        let model = try TuistGraph.ResourceFileElement.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            includeFiles: { !FileHandler.shared.isFolder($0) }
        )

        // Then
        let documentationPath = temporaryPath.appending(component: "Documentation").pathString
        XCTAssertPrinterOutputContains(
            "'\(documentationPath)' is a directory, try using: '\(documentationPath)/**' to list its files"
        )
        XCTAssertEqual(model, [])
    }

    func test_from_outputs_a_warning_when_the_folder_reference_is_invalid() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "README.md",
        ])

        let manifest = ProjectDescription.ResourceFileElement.folderReference(path: "README.md")

        // When
        let model = try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertPrinterOutputContains("README.md is not a directory - folder reference paths need to point to directories")
        XCTAssertEqual(model, [])
    }

    func test_resourceFileElement_warning_withMissingFolderReference() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.ResourceFileElement.folderReference(path: "Documentation")

        // When
        let model = try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertPrinterOutputContains("Documentation does not exist")
        XCTAssertEqual(model, [])
    }

    func test_throws_when_the_glob_is_invalid() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "invalid/path/**/*")
        let invalidGlob = InvalidGlob(
            pattern: temporaryPath.appending(RelativePath("invalid/path/**/*")).pathString,
            nonExistentPath: temporaryPath.appending(RelativePath("invalid/path/"))
        )
        let error = GlobError.nonExistentDirectory(invalidGlob)

        // Then
        XCTAssertThrowsSpecific(
            try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths),
            error
        )
    }

    func test_excluding_file() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        let includedResource = resourcesFolder.appending(component: "included.xib")
        try fileHandler.createFolder(resourcesFolder)
        try fileHandler.write("", path: includedResource, atomically: true)
        try fileHandler.write("", path: resourcesFolder.appending(component: "excluded.xib"), atomically: true)
        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**", excluding: ["Resources/excluded.xib"])

        // Then
        XCTAssertEqual(
            try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths),
            [
                .file(path: resourcesFolder, tags: []),
                .file(path: includedResource, tags: []),
            ]
        )
    }

    func test_excluding_folder() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        let excludedResourcesFolder = resourcesFolder.appending(component: "Excluded")
        let includedResource = resourcesFolder.appending(component: "included.xib")
        try fileHandler.createFolder(resourcesFolder)
        try fileHandler.write("", path: includedResource, atomically: true)
        try fileHandler.write("", path: excludedResourcesFolder.appending(component: "excluded.xib"), atomically: true)
        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**", excluding: ["Resources/Excluded"])

        // Then
        XCTAssertEqual(
            try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths),
            [
                .file(path: resourcesFolder, tags: []),
                .file(path: includedResource, tags: []),
            ]
        )
    }

    func test_excluding_glob() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        let excludedResourcesFolder = resourcesFolder.appending(component: "Excluded")
        let includedResource = resourcesFolder.appending(component: "included.xib")
        try fileHandler.createFolder(resourcesFolder)
        try fileHandler.write("", path: includedResource, atomically: true)
        try fileHandler.write("", path: excludedResourcesFolder.appending(component: "excluded.xib"), atomically: true)
        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**", excluding: ["Resources/Excluded/**"])

        // Then
        XCTAssertEqual(
            try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths),
            [
                .file(path: resourcesFolder, tags: []),
                .file(path: includedResource, tags: []),
            ]
        )
    }

    func test_excluding_when_pattern_is_file() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        try fileHandler.createFolder(resourcesFolder)
        try fileHandler.write("", path: resourcesFolder.appending(component: "excluded.xib"), atomically: true)
        let manifest = ProjectDescription.ResourceFileElement.glob(
            pattern: "Resources/excluded.xib",
            excluding: ["Resources/excluded.xib"]
        )

        // Then
        XCTAssertEqual(
            try TuistGraph.ResourceFileElement.from(manifest: manifest, generatorPaths: generatorPaths),
            []
        )
    }
}
