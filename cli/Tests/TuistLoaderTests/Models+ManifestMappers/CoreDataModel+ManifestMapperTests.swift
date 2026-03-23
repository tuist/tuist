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

struct CoreDataModelManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func test_from() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try FileHandler.shared.touch(temporaryPath.appending(component: "model.xcdatamodeld"))
        let manifest = ProjectDescription.CoreDataModel.coreDataModel(
            "model.xcdatamodeld",
            currentVersion: "1"
        )

        // When
        let model = try await XcodeGraph.CoreDataModel.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(model.path == (try generatorPaths.resolve(path: manifest.path)))
        #expect(model.currentVersion == manifest.currentVersion)
    }

    @Test(.inTemporaryDirectory) func from_getsCurrentVersionFrom_file_xccurrentversion() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: temporaryPath.appending(component: "model.xcdatamodeld").pathString),
            withIntermediateDirectories: false
        )
        try createVersionFile(xcVersion: xcVersionDataString(), temporaryPath: temporaryPath)

        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel.coreDataModel("model.xcdatamodeld")

        // When
        let model = try await XcodeGraph.CoreDataModel.from(
            manifest: manifestWithoutCurrentVersion,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(model.currentVersion == "83")
    }

    @Test(.inTemporaryDirectory) func from_getsCurrentVersionFrom_file_xccurrentversion_butCannotFindVersion() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: temporaryPath.appending(component: "model.xcdatamodeld").pathString),
            withIntermediateDirectories: false
        )
        try createVersionFile(
            xcVersion: "Let's say that apple changes the format without telling anyone, being typical Apple.",
            temporaryPath: temporaryPath
        )

        // When
        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel.coreDataModel("model.xcdatamodeld")

        // Then
        await #expect(throws: (any Error).self) {
            try await XcodeGraph.CoreDataModel.from(
                manifest: manifestWithoutCurrentVersion,
                generatorPaths: generatorPaths,
                fileSystem: self.fileSystem
            )
        }
    }

    @Test(.inTemporaryDirectory) func from_getsCurrentVersionFrom_file_xccurrentversion_butFileDoesNotExist() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel.coreDataModel("model.xcdatamodeld")

        // When
        let got = try await XcodeGraph.CoreDataModel.from(
            manifest: manifestWithoutCurrentVersion,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        #expect(
            got ==
            XcodeGraph.CoreDataModel(
                path: temporaryPath.appending(component: "model.xcdatamodeld"),
                versions: [],
                currentVersion: "model"
            )
        )
    }

    private func createVersionFile(xcVersion: String, temporaryPath: AbsolutePath) throws {
        let urlToCurrentVersion = temporaryPath.appending(try RelativePath(validating: "model.xcdatamodeld"))
            .appending(component: ".xccurrentversion")
        let data = try #require(xcVersion.data(using: .utf8))
        try data.write(to: URL(fileURLWithPath: urlToCurrentVersion.pathString))
    }

    private func xcVersionDataString() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>_XCCurrentVersionName</key>
        <string>83.xcdatamodel</string>
        </dict>
        </plist>
        """
    }
}
