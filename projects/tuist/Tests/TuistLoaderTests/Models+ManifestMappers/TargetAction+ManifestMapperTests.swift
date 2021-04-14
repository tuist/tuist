import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class TargetActionManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.TargetAction.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"]
        )
        // When
        let model = try TuistGraph.TargetAction.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool("my_tool", ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
    }

    func test_doesntGlob_whenVariable() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.TargetAction.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"],
            inputPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            inputFileListPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            outputPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            outputFileListPaths: ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        // When
        let model = try TuistGraph.TargetAction.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool("my_tool", ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
        XCTAssertEqual(model.inputPaths, [temporaryPath.appending(RelativePath("$(SRCROOT)/foo/bar/**/*.swift"))])
        XCTAssertEqual(model.inputFileListPaths, [temporaryPath.appending(RelativePath("$(SRCROOT)/foo/bar/**/*.swift"))])
        XCTAssertEqual(model.outputPaths, [temporaryPath.appending(RelativePath("$(SRCROOT)/foo/bar/**/*.swift"))])
        XCTAssertEqual(model.outputFileListPaths, [temporaryPath.appending(RelativePath("$(SRCROOT)/foo/bar/**/*.swift"))])
    }
}
