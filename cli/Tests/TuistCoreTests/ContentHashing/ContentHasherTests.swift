import FileSystemTesting
import Path
import Testing
import TuistSupport
@testable import TuistCore
@testable import TuistTesting

struct ContentHasherTests {
    private let subject: ContentHasher
    private let mockFileHandler: MockFileHandler

    init() throws {
        mockFileHandler = MockFileHandler(temporaryDirectory: { try #require(FileSystem.temporaryTestDirectory) })
        subject = ContentHasher()
    }

    // MARK: - Tests

    @Test(.inTemporaryDirectory) func hashstring_foo_returnsItsMd5() throws {
        // Given
        let hash = try subject.hash("foo")

        // Then
        #expect(hash == "acbd18db4cc2f85cedef654fccc4a4d8")
    }

    @Test(.inTemporaryDirectory) func hashstring_bar_returnsItsMd5() throws {
        // Given
        let hash = try subject.hash("bar")

        // Then
        #expect(hash == "37b51d194a7513e45b56f6524f2d51f2")
    }

    @Test(.inTemporaryDirectory) func hashstrings_foo_bar_returnsAnotherMd5() throws {
        // Given
        let hash = try subject.hash(["foo", "bar"])

        // Then
        #expect(hash == "3858f62230ac3c915f300c664312c63f")
    }

    @Test(.inTemporaryDirectory) func hashdict_returnsMd5OfConcatenation() throws {
        // Given
        let hash = try subject.hash(["1": "foo", "2": "bar"])
        let expectedHash = try subject.hash("1:foo-2:bar")
        // Then
        #expect(hash == expectedHash)
    }

    @Test(.inTemporaryDirectory) func hashFile_hashesTheExpectedFile() async throws {
        // Given
        let path = try writeToTemporaryPath(content: "foo")

        // When
        let hash = try await subject.hash(path: path)

        // Then
        #expect(hash == "acbd18db4cc2f85cedef654fccc4a4d8")
    }

    @Test(.inTemporaryDirectory) func hashFile_isNotHarcoded() async throws {
        // Given
        let path = try writeToTemporaryPath(content: "bar")

        // When
        let hash = try await subject.hash(path: path)

        // Then
        #expect(hash == "37b51d194a7513e45b56f6524f2d51f2")
    }

    @Test(.inTemporaryDirectory) func hashFile_whenFileDoesntExist_itThrowsFileNotFound() async throws {
        // Given
        let wrongPath = try AbsolutePath(validating: "/shakirashakira")

        // Then
        await #expect(throws: FileHandlerError.fileNotFound(wrongPath)) {
            try await subject.hash(path: wrongPath)
        }
    }

    @Test(.inTemporaryDirectory) func hash_sortedContentsOfADirectorySkippingDSStore() async throws {
        // given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let folderPath = temporaryPath.appending(component: "assets.xcassets")
        try mockFileHandler.createFolder(folderPath)

        let files = [
            "foo": "bar",
            "foo2": "bar2",
            ".ds_store": "should be ignored",
            ".DS_STORE": "should be ignored too",
        ]

        try writeFiles(to: folderPath, files: files)

        // When
        let hash = try await subject.hash(path: folderPath)

        // Then
        #expect(hash == "224e2539f52203eb33728acd228b4432-37b51d194a7513e45b56f6524f2d51f2")
    }

    @Test(.inTemporaryDirectory) func hash_ContentsOfADirectoryIncludingSymbolicLinksWithRelativePaths() async throws {
        // Given
        let fileSystem = FileSystem()
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let symbolicPath = temporaryDirectory.appending(component: "symbolic")
            let destinationPath = temporaryDirectory.appending(component: "destination")
            try await fileSystem.writeText("destination", at: destinationPath)
            try await fileSystem.createSymbolicLink(from: symbolicPath, to: RelativePath(validating: "destination"))
            try await fileSystem.createSymbolicLink(
                from: temporaryDirectory.appending(component: "non-existent-symbolic"),
                to: RelativePath(validating: "non-existent")
            )
            try await fileSystem.writeText("foo", at: temporaryDirectory.appending(component: "foo.txt"))

            // When
            let hash = try await subject.hash(path: temporaryDirectory)

            // Then
            #expect(
                hash ==
                    "6990a54322d9232390a784c5c9247dd6-6990a54322d9232390a784c5c9247dd6-acbd18db4cc2f85cedef654fccc4a4d8"
            )
        }
    }

    // MARK: - Private

    private func writeToTemporaryPath(fileName: String = "foo", content: String = "foo") throws -> AbsolutePath {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryPath.appending(component: fileName)
        try mockFileHandler.write(content, path: path, atomically: true)
        return path
    }

    private func writeFiles(to folder: AbsolutePath, files: [String: String]) throws {
        for file in files {
            try mockFileHandler.write(file.value, path: folder.appending(component: file.key), atomically: true)
        }
    }
}
