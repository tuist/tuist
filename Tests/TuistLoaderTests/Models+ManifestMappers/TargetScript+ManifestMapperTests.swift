import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class TargetScriptManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.TargetScript.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"]
        )
        // When
        let model = try TuistGraph.TargetScript.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool(path: "my_tool", args: ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
    }

    func test_doesntGlob_whenVariable() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "foo/bar/a.swift",
            "foo/bar/b.swift",
            "foo/bar/aTests.swift",
            "foo/bar/bTests.swift",
            "foo/bar/kTests.kt",
            "foo/bar/c/c.swift",
            "foo/bar/c/cTests.swift",
        ])

        let manifest = ProjectDescription.TargetScript.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"],
            inputPaths: [
                "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}",
                "foo/bar/**/*.swift",
            ],
            inputFileListPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            outputPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            outputFileListPaths: ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        // When
        let model = try TuistGraph.TargetScript.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        let relativeSources = try model.inputPaths.map { try AbsolutePath(validating: $0).relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}",
            "foo/bar/a.swift",
            "foo/bar/b.swift",
            "foo/bar/aTests.swift",
            "foo/bar/bTests.swift",
            "foo/bar/c/c.swift",
            "foo/bar/c/cTests.swift",
        ]))

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool(path: "my_tool", args: ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
        XCTAssertEqual(
            model.inputFileListPaths,
            [temporaryPath.appending(try RelativePath(validating: "$(SRCROOT)/foo/bar/**/*.swift"))]
        )
        XCTAssertEqual(
            model.outputPaths,
            [temporaryPath.appending(try RelativePath(validating: "$(SRCROOT)/foo/bar/**/*.swift")).pathString]
        )
        XCTAssertEqual(
            model.outputFileListPaths,
            [temporaryPath.appending(try RelativePath(validating: "$(SRCROOT)/foo/bar/**/*.swift"))]
        )
    }

    func test_glob_whenExcluding() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "foo/bar/a.swift",
            "foo/bar/b.swift",
            "foo/bar/aTests.swift",
            "foo/bar/bTests.swift",
            "foo/bar/kTests.kt",
            "foo/bar/c/c.swift",
            "foo/bar/c/cTests.swift",
        ])

        let manifest = ProjectDescription.TargetScript.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"],
            inputPaths: [
                .glob(
                    "foo/bar/**/*.swift",
                    excluding: [
                        "foo/bar/**/*Tests.swift",
                        "foo/bar/**/*b.swift",
                    ]
                ),
            ],
            inputFileListPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            outputPaths: ["$(SRCROOT)/foo/bar/**/*.swift"],
            outputFileListPaths: ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        // When
        let model = try TuistGraph.TargetScript.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        let relativeSources = try model.inputPaths.map { try AbsolutePath(validating: $0).relative(to: temporaryPath).pathString }

        XCTAssertEqual(Set(relativeSources), Set([
            "foo/bar/a.swift",
            "foo/bar/c/c.swift",
        ]))

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool(path: "my_tool", args: ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
        XCTAssertEqual(
            model.inputFileListPaths,
            [temporaryPath.appending(try RelativePath(validating: "$(SRCROOT)/foo/bar/**/*.swift"))]
        )
        XCTAssertEqual(
            model.outputPaths,
            [temporaryPath.appending(try RelativePath(validating: "$(SRCROOT)/foo/bar/**/*.swift")).pathString]
        )
        XCTAssertEqual(
            model.outputFileListPaths,
            [temporaryPath.appending(try RelativePath(validating: "$(SRCROOT)/foo/bar/**/*.swift"))]
        )
    }
}
