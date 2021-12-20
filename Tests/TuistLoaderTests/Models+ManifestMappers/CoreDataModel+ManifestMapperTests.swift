import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CoreDataModelManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try FileHandler.shared.touch(temporaryPath.appending(component: "model.xcdatamodeld"))
        let manifest = ProjectDescription.CoreDataModel(
            "model.xcdatamodeld",
            currentVersion: "1"
        )

        // When
        let model = try TuistGraph.CoreDataModel.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertTrue(try coreDataModel(model, matches: manifest, at: temporaryPath, generatorPaths: generatorPaths))
    }

    func test_from_getsCurrentVersionFrom_file_xccurrentversion() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        try FileManager.default.createDirectory(
            at: temporaryPath.appending(component: "model.xcdatamodeld").asURL,
            withIntermediateDirectories: false
        )
        try createVersionFile(xcVersion: xcVersionDataString(), temporaryPath: temporaryPath)

        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel("model.xcdatamodeld")

        // When
        let model = try TuistGraph.CoreDataModel.from(manifest: manifestWithoutCurrentVersion, generatorPaths: generatorPaths)

        let manifestWithCurrentVersionExplicitly = ProjectDescription.CoreDataModel("model.xcdatamodeld", currentVersion: "83")

        // Then
        XCTAssertTrue(try coreDataModel(
            model,
            matches: manifestWithCurrentVersionExplicitly,
            at: temporaryPath,
            generatorPaths: generatorPaths
        ))
    }

    func test_from_getsCurrentVersionFrom_file_xccurrentversion_butCannotFindVersion() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        try FileManager.default.createDirectory(
            at: temporaryPath.appending(component: "model.xcdatamodeld").asURL,
            withIntermediateDirectories: false
        )
        try createVersionFile(
            xcVersion: "Let's say that apple changes the format without telling anyone, being typical Apple.",
            temporaryPath: temporaryPath
        )

        // When
        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel("model.xcdatamodeld")

        // Then
        XCTAssertThrowsError(
            try TuistGraph.CoreDataModel.from(manifest: manifestWithoutCurrentVersion, generatorPaths: generatorPaths)
        )
    }

    func test_from_getsCurrentVersionFrom_file_xccurrentversion_butFileDoesNotExist() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        // When
        let manifestWithoutCurrentVersion = ProjectDescription.CoreDataModel("model.xcdatamodeld")

        XCTAssertEqual(
            try TuistGraph.CoreDataModel.from(
                manifest: manifestWithoutCurrentVersion,
                generatorPaths: generatorPaths
            ),
            TuistGraph.CoreDataModel(
                path: temporaryPath.appending(component: "model.xcdatamodeld"),
                versions: [],
                currentVersion: "model"
            )
        )
    }

    private func createVersionFile(xcVersion: String, temporaryPath: AbsolutePath) throws {
        let urlToCurrentVersion = temporaryPath.appending(RelativePath("model.xcdatamodeld"))
            .appending(component: ".xccurrentversion")
        let data = try XCTUnwrap(xcVersion.data(using: .utf8))
        try data.write(to: urlToCurrentVersion.asURL)
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
