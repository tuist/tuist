import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class CoreDataModelManifestMapperTests: TuistUnitTestCase {
    func test_from() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
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
        XCTAssertTrue(try coreDataModel(model, matches: manifest, at: temporaryPath, generatorPaths: generatorPaths))
    }

    func test_from_getsCurrentVersionFrom_file_xccurrentversion() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
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

        let manifestWithCurrentVersionExplicitly = ProjectDescription.CoreDataModel.coreDataModel(
            "model.xcdatamodeld",
            currentVersion: "83"
        )

        // Then
        XCTAssertTrue(try coreDataModel(
            model,
            matches: manifestWithCurrentVersionExplicitly,
            at: temporaryPath,
            generatorPaths: generatorPaths
        ))
    }

    func test_from_getsCurrentVersionFrom_file_xccurrentversion_butCannotFindVersion() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
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
        await XCTAssertThrows(
            try await XcodeGraph.CoreDataModel.from(
                manifest: manifestWithoutCurrentVersion,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )
        )
    }

    func test_from_getsCurrentVersionFrom_file_xccurrentversion_butFileDoesNotExist() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel.coreDataModel("model.xcdatamodeld")

        // When
        let got = try await XcodeGraph.CoreDataModel.from(
            manifest: manifestWithoutCurrentVersion,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(
            got,
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
        let data = try XCTUnwrap(xcVersion.data(using: .utf8))
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
