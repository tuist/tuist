import Foundation
import Path
import TuistTesting
import FileSystemTesting
import Testing

@testable import TuistSupport

struct FileSystemExtrasTests {
    @Test(.inTemporaryDirectory)
    func test_throwingGlob_throws_when_directoryDoesntExist() async throws {
        // Given
        let dir = try #require(FileSystem.temporaryTestDirectory)

        // Then
        await #expect(throws: GlobError.nonExistentDirectory(InvalidGlob(
                pattern: dir.appending(try RelativePath(validating: "invalid/path/**/*")).pathString,
                nonExistentPath: dir.appending(try RelativePath(validating: "invalid/path/"))
            ))) { try await fileSystem.throwingGlob(directory: dir, include: ["invalid/path/**/*"]).collect() }
    }

    @Test(.inTemporaryDirectory)
    func test_throwingGlob_throws_when_directoryExists() async throws {
        // Given
        let files = try await createFiles(["path/nested/file.swift"])
        let parentDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When
        let got = try await fileSystem.glob(
            directory: parentDirectory,
            include: ["path/**/*.swift"]
        )
        .collect()

        // Then
        #expect(got == files)
    }
}
