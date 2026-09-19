import Foundation
import Path
import TuistTesting
import XCTest

@testable import TuistSupport

final class FileSystemExtrasTests: TuistUnitTestCase {
    func test_throwingGlob_throws_when_directoryDoesntExist() async throws {
        // Given
        let dir = try temporaryPath()

        // Then
        await XCTAssertThrowsSpecific(
            try await fileSystem.throwingGlob(directory: dir, include: ["invalid/path/**/*"]).collect(),
            GlobError.nonExistentDirectory(InvalidGlob(
                pattern: dir.appending(try RelativePath(validating: "invalid/path/**/*")).pathString,
                nonExistentPath: dir.appending(try RelativePath(validating: "invalid/path/"))
            ))
        )
    }

    func test_throwingGlob_throws_when_directoryExists() async throws {
        // Given
        let files = try await createFiles(["path/nested/file.swift"])
        let parentDirectory = try temporaryPath()

        // When
        let got = try await fileSystem.glob(
            directory: parentDirectory,
            include: ["path/**/*.swift"]
        )
        .collect()

        // Then
        XCTAssertEqual(
            got,
            files
        )
    }

    func test_manifestGlob_recordsEachExpansionWhileDurationsAreBound() async throws {
        // Given
        let files = try await createFiles(["Sources/A.swift", "Resources/Image.png"])
        let directory = try temporaryPath()
        let durations = ManifestGlobDurations()

        // When
        let (swiftFiles, pngFiles) = try await ManifestGlobDurations.$current.withValue(durations) {
            (
                try await fileSystem.manifestGlob(directory: directory, include: ["Sources/**/*.swift"]).collect(),
                try await fileSystem.manifestGlob(directory: directory, include: ["Resources/*.png"]).collect()
            )
        }

        // Then
        XCTAssertEqual(swiftFiles, [files[0]])
        XCTAssertEqual(pngFiles, [files[1]])
        let summary = try XCTUnwrap(durations.summary())
        XCTAssertTrue(summary.hasPrefix("Manifest globs: 2 expansions took "))
        XCTAssertTrue(summary.contains(directory.appending(try RelativePath(validating: "Sources/**/*.swift")).pathString))
        XCTAssertTrue(summary.contains(directory.appending(try RelativePath(validating: "Resources/*.png")).pathString))
    }

    func test_manifestGlobDurations_summaryIsNilWhenNothingWasRecorded() {
        XCTAssertNil(ManifestGlobDurations().summary())
    }

    func test_manifestGlobDurations_summaryKeepsOnlyTheSlowestExpansions() throws {
        // Given
        let durations = ManifestGlobDurations(slowestLimit: 2)

        // When
        durations.record(pattern: "/fast", duration: 1)
        durations.record(pattern: "/slowest", duration: 3)
        durations.record(pattern: "/slow", duration: 2)

        // Then
        XCTAssertEqual(
            durations.summary(),
            """
            Manifest globs: 3 expansions took 6.000s in total. Slowest:
              3.000s /slowest
              2.000s /slow
            """
        )
    }
}
