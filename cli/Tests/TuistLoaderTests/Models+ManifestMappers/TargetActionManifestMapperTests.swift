import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupportTesting
import XCTest

@testable import TuistLoader

final class TargetActionManifestMapperTests: TuistUnitTestCase {
    // MARK: - Output paths: non-existent files must be included

    /// Regression test for https://github.com/tuist/tuist/issues/5925
    ///
    /// A TargetScript whose `outputPaths` reference files that do **not yet exist** on disk
    /// should still have those paths included in the generated build phase.  Prior to the fix,
    /// the glob-based resolution silently dropped every missing file.
    func test_from_outputPaths_includesNonExistentFiles() async throws {
        // GIVEN
        let temporaryDirectory = try temporaryPath()
        // Create the project directory but deliberately do NOT create File.swift.
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory)
        let nonExistentOutputPath = "Sources/Generated/File.swift"

        let manifest = ProjectDescription.TargetScript.pre(
            script: "echo hello",
            name: "Generate File",
            outputPaths: [.relativeToManifest(nonExistentOutputPath)]
        )

        // WHEN
        let targetScript = try await TuistCore.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // THEN
        let expectedAbsoluteOutput = temporaryDirectory
            .appending(try RelativePath(validating: nonExistentOutputPath))
            .pathString

        XCTAssertEqual(
            targetScript.outputPaths,
            [expectedAbsoluteOutput],
            "Output path for a non-existent file must still be included in the generated build phase."
        )
    }

    /// Existing output files should continue to be included (no regression).
    func test_from_outputPaths_includesExistingFiles() async throws {
        // GIVEN
        let temporaryDirectory = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory)

        // Create the file so it exists on disk.
        let existingRelativePath = "Sources/Generated/Existing.swift"
        let existingAbsolutePath = temporaryDirectory
            .appending(try RelativePath(validating: existingRelativePath))
        try fileHandler.createFolder(existingAbsolutePath.parentDirectory)
        try fileHandler.touch(existingAbsolutePath)

        let manifest = ProjectDescription.TargetScript.pre(
            script: "echo hello",
            name: "Generate File",
            outputPaths: [.relativeToManifest(existingRelativePath)]
        )

        // WHEN
        let targetScript = try await TuistCore.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // THEN
        XCTAssertEqual(
            targetScript.outputPaths,
            [existingAbsolutePath.pathString],
            "Output path for an existing file must be included in the generated build phase."
        )
    }

    /// Output paths that contain Xcode build variables (e.g. `$(DERIVED_FILE_DIR)`) must be
    /// passed through unchanged — they cannot be resolved to an absolute path at generate time.
    func test_from_outputPaths_passesThroughBuildVariables() async throws {
        // GIVEN
        let temporaryDirectory = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory)

        let manifest = ProjectDescription.TargetScript.pre(
            script: "echo hello",
            name: "Generate File",
            outputPaths: [.path("$(DERIVED_FILE_DIR)/Generated.swift")]
        )

        // WHEN
        let targetScript = try await TuistCore.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // THEN – the variable-containing path should be present (not silently dropped).
        XCTAssertFalse(
            targetScript.outputPaths.isEmpty,
            "Output paths containing build variables must not be silently dropped."
        )
        XCTAssertTrue(
            targetScript.outputPaths.allSatisfy { $0.contains("DERIVED_FILE_DIR") },
            "Output paths containing build variables should be preserved as-is."
        )
    }

    // MARK: - Input paths: existing behaviour should be preserved

    /// Input paths that do not exist should remain excluded (inputs are globbed, so only
    /// present files are returned — this preserves existing behaviour).
    func test_from_inputPaths_excludesNonExistentFiles() async throws {
        // GIVEN
        let temporaryDirectory = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory)

        let manifest = ProjectDescription.TargetScript.pre(
            script: "echo hello",
            name: "Script",
            inputPaths: [.relativeToManifest("NonExistent/Input.swift")]
        )

        // WHEN
        let targetScript = try await TuistCore.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // THEN
        XCTAssertTrue(
            targetScript.inputPaths.isEmpty,
            "Non-existent input files should be excluded (glob returns nothing for missing files)."
        )
    }

    // MARK: - Multiple output paths

    /// A mix of existing and non-existing output paths should both be included.
    func test_from_outputPaths_includesMixedExistenceFiles() async throws {
        // GIVEN
        let temporaryDirectory = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory)

        let existingRelPath = "Sources/Existing.swift"
        let existingAbsPath = temporaryDirectory
            .appending(try RelativePath(validating: existingRelPath))
        try fileHandler.createFolder(existingAbsPath.parentDirectory)
        try fileHandler.touch(existingAbsPath)

        let nonExistentRelPath = "Sources/Generated/Missing.swift"
        let nonExistentAbsPath = temporaryDirectory
            .appending(try RelativePath(validating: nonExistentRelPath))
            .pathString

        let manifest = ProjectDescription.TargetScript.pre(
            script: "echo hello",
            name: "Generate",
            outputPaths: [
                .relativeToManifest(existingRelPath),
                .relativeToManifest(nonExistentRelPath),
            ]
        )

        // WHEN
        let targetScript = try await TuistCore.TargetScript.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        // THEN
        XCTAssertEqual(
            targetScript.outputPaths.count,
            2,
            "Both existing and non-existing output paths must be included."
        )
        XCTAssertTrue(targetScript.outputPaths.contains(existingAbsPath.pathString))
        XCTAssertTrue(targetScript.outputPaths.contains(nonExistentAbsPath))
    }
}
