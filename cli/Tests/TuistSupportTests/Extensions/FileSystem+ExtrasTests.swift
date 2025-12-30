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
}
