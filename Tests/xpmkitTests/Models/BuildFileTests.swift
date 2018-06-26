import Basic
import Foundation
import XCTest
@testable import xpmkit

final class BuildFileErrorTests: XCTestCase {
    func test_description_when_invalidBuildFileType() {
        let error = BuildFileError.invalidBuildFileType("invalid_type")
        XCTAssertEqual(error.description, "Invalid build file type: invalid_type")
    }

    func test_type_when_invalidBuildFileType() {
        let error = BuildFileError.invalidBuildFileType("invalid_type")
        XCTAssertEqual(error.type, .bug)
    }
}

final class BaseResourcesBuildFileTests: XCTestCase {
    func test_from_throws_when_invalidType() {
        let json = JSON.dictionary(["type": "invalid".toJSON()])
        let projectPath = AbsolutePath("/test")
        let context = GraphLoaderContext()
        let expectedError = BuildFileError.invalidBuildFileType("invalid")
        XCTAssertThrowsError(try BaseResourcesBuildFile.from(json: json,
                                                             projectPath: projectPath,
                                                             context: context)) {
            XCTAssertEqual($0 as? BuildFileError, expectedError)
        }
    }
}

final class ResourcesBuildFileTests: XCTestCase {
    var context: GraphLoaderContexting!

    override func setUp() {
        super.setUp()
        context = GraphLoaderContext()
    }

    func test_init_discardsInvalidFiles() throws {
        let fileManager = FileManager.default
        let directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let frameworkPath = directory.path.appending(components: "Test.framework")
        let folderPath = directory.path.appending(components: "Test")
        let imagePath = directory.path.appending(components: "Image.png")

        try fileManager.createDirectory(atPath: frameworkPath.asString,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
        try fileManager.createDirectory(atPath: folderPath.asString,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
        try Data().write(to: URL(fileURLWithPath: imagePath.asString))

        let json = JSON.dictionary(["pattern": JSON.string("**")])
        let buildFile = try ResourcesBuildFile(json: json,
                                               projectPath: directory.path,
                                               context: context)

        XCTAssertEqual(buildFile.paths.count, 2)
        XCTAssertEqual(buildFile.paths.first, imagePath)
        XCTAssertEqual(buildFile.paths.last, frameworkPath)
    }

    func test_validFolderExtensions() {
        XCTAssertEqual(ResourcesBuildFile.validFolderExtensions, ["framework", "bundle", "app"])
    }
}

final class SourcesBuildFileTests: XCTestCase {
    var context: GraphLoaderContexting!

    override func setUp() {
        super.setUp()
        context = GraphLoaderContext()
    }

    func test_init_discardsInvalidFiles() throws {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let bodyPath = directory.path.appending(components: "File.m")
        let headerPath = directory.path.appending(components: "File.h")

        try Data().write(to: URL(fileURLWithPath: bodyPath.asString))
        try Data().write(to: URL(fileURLWithPath: headerPath.asString))

        let json = JSON.dictionary(["pattern": JSON.string("**")])
        let buildFile = try SourcesBuildFile(json: json,
                                             projectPath: directory.path,
                                             context: context)

        XCTAssertEqual(buildFile.paths.count, 1)
        XCTAssertEqual(buildFile.paths.first, bodyPath)
    }

    func test_validExtensions() {
        XCTAssertEqual(SourcesBuildFile.validExtensions, ["m", "swift", "mm"])
    }
}

final class HeadersBuildFileTests: XCTestCase {
    var context: GraphLoaderContexting!

    override func setUp() {
        super.setUp()
        context = GraphLoaderContext()
    }

    func test_init_discardsInvalidFiles() throws {
        let directory = try TemporaryDirectory(removeTreeOnDeinit: true)
        let bodyPath = directory.path.appending(components: "File.m")
        let headerPath = directory.path.appending(components: "File.h")

        try Data().write(to: URL(fileURLWithPath: bodyPath.asString))
        try Data().write(to: URL(fileURLWithPath: headerPath.asString))

        let json = JSON.dictionary([
            "pattern": JSON.string("**"),
            "access_level": JSON.string("public"),
        ])
        let buildFile = try HeadersBuildFile(json: json,
                                             projectPath: directory.path,
                                             context: context)

        XCTAssertEqual(buildFile.paths.count, 1)
        XCTAssertEqual(buildFile.paths.first, headerPath)
    }

    func test_validExtensions() {
        XCTAssertEqual(HeadersBuildFile.validExtensions, ["h", "hh", "pch"])
    }
}
