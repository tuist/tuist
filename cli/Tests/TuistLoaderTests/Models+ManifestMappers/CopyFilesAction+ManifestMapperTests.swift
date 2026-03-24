import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct CopyFilesManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func from_with_regular_files() async throws {
        // Given
        let files = [
            "Fonts/font1.ttf",
            "Fonts/font2.ttf",
            "Fonts/font3.ttf",
        ]

        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles(files)

        let manifest = ProjectDescription.CopyFilesAction.resources(
            name: "Copy Fonts",
            subpath: "Fonts",
            files: ["Fonts/**"]
        )

        // When
        let model = try await XcodeGraph.CopyFilesAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(model.name == "Copy Fonts")
        #expect(model.destination == .resources)
        #expect(model.subpath == "Fonts")
        #expect(model.files == (try files.map { .file(path: temporaryPath.appending(try RelativePath(validating: $0))) }))
    }

    @Test(.inTemporaryDirectory) func from_with_package_files() async throws {
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

        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles(files)

        let manifest = ProjectDescription.CopyFilesAction.sharedSupport(
            name: "Copy Templates",
            subpath: "Templates",
            files: ["SharedSupport/**"]
        )

        // When
        let model = try await XcodeGraph.CopyFilesAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(model.name == "Copy Templates")
        #expect(model.destination == .sharedSupport)
        #expect(model.subpath == "Templates")
        #expect(
            model.files ==
                (try cleanFiles.map { .file(path: temporaryPath.appending(try RelativePath(validating: $0))) })
        )
    }
}
