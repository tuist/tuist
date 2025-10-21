import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class TargetScriptManifestMapperTests: TuistUnitTestCase {
    func test_from() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        let manifest = ProjectDescription.TargetScript.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"]
        )
        // When
        let model = try await XcodeGraph.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool(path: "my_tool", args: ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
    }

    func test_doesntGlob_whenVariable() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        try await createFiles([
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
        let model = try await XcodeGraph.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        let relativeSources = model.inputPaths
            .map { (try? AbsolutePath(validating: $0).relative(to: temporaryPath).pathString) ?? $0 }

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
            ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        XCTAssertEqual(
            model.outputPaths,
            ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        XCTAssertEqual(
            model.outputFileListPaths,
            ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
    }

    func test_doesntGlob_whenNotGlobPattern() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        try await createFiles([
            "foo/bar/a.swift",
            "foo/bar/b.swift",
        ])

        let manifest = ProjectDescription.TargetScript.test(
            name: "MyScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1", "arg2"],
            inputPaths: [],
            inputFileListPaths: ["foo/bar/inputPathList1.swift"],
            outputPaths: ["foo/bar/outputPath1.swift"],
            outputFileListPaths: ["foo/bar/outputPathList1.swift"]
        )
        // When
        let model = try await XcodeGraph.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool(path: "my_tool", args: ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
        XCTAssertEqual(
            model.inputFileListPaths,
            ["foo/bar/inputPathList1.swift"]
        )
        XCTAssertEqual(
            model.outputPaths,
            ["foo/bar/outputPath1.swift"]
        )
        XCTAssertEqual(
            model.outputFileListPaths,
            ["foo/bar/outputPathList1.swift"]
        )
    }

    func test_glob_whenExcluding() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )
        try await createFiles([
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
        let model = try await XcodeGraph.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        let relativeSources = model.inputPaths
            .map { (try? AbsolutePath(validating: $0).relative(to: temporaryPath).pathString) ?? $0 }

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
            ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        XCTAssertEqual(
            model.outputPaths,
            ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
        XCTAssertEqual(
            model.outputFileListPaths,
            ["$(SRCROOT)/foo/bar/**/*.swift"]
        )
    }

    func test_relativeToManifest_paths_are_kept_as_strings() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )

        let manifest = ProjectDescription.TargetScript.test(
            name: "TestScript",
            tool: "my_tool",
            order: .pre,
            arguments: ["arg1"],
            inputPaths: [],
            inputFileListPaths: [
                .relativeToManifest("relative/to/manifest.txt"),
                .relativeToRoot("relative/to/root.txt"),
            ],
            outputPaths: [
                .relativeToManifest("output/manifest.txt"),
                .relativeToRoot("output/root.txt"),
            ],
            outputFileListPaths: [
                .relativeToManifest("output_list/manifest.txt"),
            ]
        )

        // When
        let model = try await XcodeGraph.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        // relativeToManifest paths should be kept as strings
        XCTAssertTrue(model.inputFileListPaths.contains("relative/to/manifest.txt"))
        XCTAssertTrue(model.outputPaths.contains("output/manifest.txt"))
        XCTAssertTrue(model.outputFileListPaths.contains("output_list/manifest.txt"))

        // relativeToRoot and relativeToCurrentFile should be resolved to absolute paths
        let expectedRootPath = temporaryPath.appending(try RelativePath(validating: "relative/to/root.txt")).pathString
        let expectedOutputRootPath = temporaryPath.appending(try RelativePath(validating: "output/root.txt")).pathString

        XCTAssertTrue(model.inputFileListPaths.contains(expectedRootPath))
        XCTAssertTrue(model.outputPaths.contains(expectedOutputRootPath))
    }

    func test_inputPaths_with_build_variables_are_kept_as_strings() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let rootDirectory = temporaryPath
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: rootDirectory
        )

        let manifest = ProjectDescription.TargetScript.test(
            name: "RunSwiftGen",
            tool: "path/to/script",
            order: .pre,
            arguments: [],
            inputPaths: [
                "$(SRCROOT)/Resources/Images/Images.xcassets",
                "$(SRCROOT)/Resources/Images/Symbols.xcassets",
            ],
            outputPaths: [
                "$(SRCROOT)/Resources/SwiftGen/Assets.swift",
            ]
        )

        // When
        let model = try await XcodeGraph.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // Then
        // Paths with build variables should be kept as-is, not resolved to absolute paths
        XCTAssertEqual(model.inputPaths, [
            "$(SRCROOT)/Resources/Images/Images.xcassets",
            "$(SRCROOT)/Resources/Images/Symbols.xcassets",
        ])
        XCTAssertEqual(model.outputPaths, [
            "$(SRCROOT)/Resources/SwiftGen/Assets.swift",
        ])
    }
}
