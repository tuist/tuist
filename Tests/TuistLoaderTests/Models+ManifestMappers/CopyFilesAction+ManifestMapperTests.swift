import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CopyFilesManifestMapperTests: TuistUnitTestCase {
    func test_from_with_regular_files() throws {
        // Given
        let files = [
            "Fonts/font1.ttf",
            "Fonts/font2.ttf",
            "Fonts/font3.ttf",
        ]

        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles(files)

        let manifest = ProjectDescription.CopyFilesAction.resources(
            name: "Copy Fonts",
            subpath: "Fonts",
            files: "Fonts/**"
        )

        // When
        let model = try TuistGraph.CopyFilesAction.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(model.name, "Copy Fonts")
        XCTAssertEqual(model.destination, .resources)
        XCTAssertEqual(model.subpath, "Fonts")
        XCTAssertEqual(model.files, files.map { .file(path: temporaryPath.appending(RelativePath($0))) })
    }

    func test_from_with_package_files() throws {
        // Given
        let files = [
            "SharedSupport/simple-tuist.rtf",
            "SharedSupport/tuist.rtfd/TXT.rtf",
            "SharedSupport/tuist.rtfd/image.jpg",
        ]

        let cleanFiles = [
            "SharedSupport/simple-tuist.rtf",
            "SharedSupport/tuist.rtfd",
        ]

        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles(files)

        let manifest = ProjectDescription.CopyFilesAction.sharedSupport(
            name: "Copy Templates",
            subpath: "Templates",
            files: "SharedSupport/**"
        )

        // When
        let model = try TuistGraph.CopyFilesAction.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(model.name, "Copy Templates")
        XCTAssertEqual(model.destination, .sharedSupport)
        XCTAssertEqual(model.subpath, "Templates")
        XCTAssertEqual(model.files, cleanFiles.map { .file(path: temporaryPath.appending(RelativePath($0))) })
    }
}
