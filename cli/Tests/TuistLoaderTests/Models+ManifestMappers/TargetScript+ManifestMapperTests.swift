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

struct TargetScriptManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func test_from() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
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
        #expect(model.name == "MyScript")
        #expect(model.script == .tool(path: "my_tool", args: ["arg1", "arg2"]))
        #expect(model.order == .pre)
    }

    @Test(.inTemporaryDirectory) func test_doesntGlob_whenVariable() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let files = [
            "foo/bar/a.swift",
            "foo/bar/b.swift",
            "foo/bar/aTests.swift",
            "foo/bar/bTests.swift",
            "foo/bar/kTests.kt",
            "foo/bar/c/c.swift",
            "foo/bar/c/cTests.swift",
        ]
        for file in files {
            let filePath = temporaryPath.appending(try RelativePath(validating: file))
            try await fileSystem.makeDirectory(at: filePath.parentDirectory)
            try await fileSystem.touch(filePath)
        }

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

        #expect(Set(relativeSources) == Set([
            "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}",
            "foo/bar/a.swift",
            "foo/bar/b.swift",
            "foo/bar/aTests.swift",
            "foo/bar/bTests.swift",
            "foo/bar/c/c.swift",
            "foo/bar/c/cTests.swift",
        ]))

        #expect(model.name == "MyScript")
        #expect(model.script == .tool(path: "my_tool", args: ["arg1", "arg2"]))
        #expect(model.order == .pre)
        #expect(model.inputFileListPaths == ["$(SRCROOT)/foo/bar/**/*.swift"])
        #expect(model.outputPaths == ["$(SRCROOT)/foo/bar/**/*.swift"])
        #expect(model.outputFileListPaths == ["$(SRCROOT)/foo/bar/**/*.swift"])
    }

    @Test(.inTemporaryDirectory) func test_doesntGlob_whenNotGlobPattern() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let files = ["foo/bar/a.swift", "foo/bar/b.swift"]
        for file in files {
            let filePath = temporaryPath.appending(try RelativePath(validating: file))
            try await fileSystem.makeDirectory(at: filePath.parentDirectory)
            try await fileSystem.touch(filePath)
        }

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
        #expect(model.name == "MyScript")
        #expect(model.script == .tool(path: "my_tool", args: ["arg1", "arg2"]))
        #expect(model.order == .pre)
        #expect(model.inputFileListPaths == ["foo/bar/inputPathList1.swift"])
        #expect(model.outputPaths == ["foo/bar/outputPath1.swift"])
        #expect(model.outputFileListPaths == ["foo/bar/outputPathList1.swift"])
    }

    @Test(.inTemporaryDirectory) func test_glob_whenExcluding() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        let files = [
            "foo/bar/a.swift",
            "foo/bar/b.swift",
            "foo/bar/aTests.swift",
            "foo/bar/bTests.swift",
            "foo/bar/kTests.kt",
            "foo/bar/c/c.swift",
            "foo/bar/c/cTests.swift",
        ]
        for file in files {
            let filePath = temporaryPath.appending(try RelativePath(validating: file))
            try await fileSystem.makeDirectory(at: filePath.parentDirectory)
            try await fileSystem.touch(filePath)
        }

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

        #expect(Set(relativeSources) == Set([
            "foo/bar/a.swift",
            "foo/bar/c/c.swift",
        ]))

        #expect(model.name == "MyScript")
        #expect(model.script == .tool(path: "my_tool", args: ["arg1", "arg2"]))
        #expect(model.order == .pre)
        #expect(model.inputFileListPaths == ["$(SRCROOT)/foo/bar/**/*.swift"])
        #expect(model.outputPaths == ["$(SRCROOT)/foo/bar/**/*.swift"])
        #expect(model.outputFileListPaths == ["$(SRCROOT)/foo/bar/**/*.swift"])
    }

    @Test(.inTemporaryDirectory) func test_relativeToManifest_paths_are_kept_as_strings() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
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
        #expect(model.inputFileListPaths.contains("relative/to/manifest.txt"))
        #expect(model.outputPaths.contains("output/manifest.txt"))
        #expect(model.outputFileListPaths.contains("output_list/manifest.txt"))

        let expectedRootPath = temporaryPath.appending(try RelativePath(validating: "relative/to/root.txt")).pathString
        let expectedOutputRootPath = temporaryPath.appending(try RelativePath(validating: "output/root.txt")).pathString

        #expect(model.inputFileListPaths.contains(expectedRootPath))
        #expect(model.outputPaths.contains(expectedOutputRootPath))
    }

    @Test(.inTemporaryDirectory) func test_inputPaths_with_build_variables_are_kept_as_strings() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
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
        #expect(model.inputPaths == [
            "$(SRCROOT)/Resources/Images/Images.xcassets",
            "$(SRCROOT)/Resources/Images/Symbols.xcassets",
        ])
        #expect(model.outputPaths == [
            "$(SRCROOT)/Resources/SwiftGen/Assets.swift",
        ])
    }
}
