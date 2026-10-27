import FileSystem
import Path
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistTesting

final class ContentHasherTests: TuistUnitTestCase {
    private var subject: ContentHasher!

    override func setUp() {
        super.setUp()
        subject = ContentHasher()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hashstring_foo_returnsItsMd5() throws {
        // Given
        let hash = try subject.hash("foo")

        // Then
        XCTAssertEqual(hash, "acbd18db4cc2f85cedef654fccc4a4d8") // This is the md5 of "foo"
    }

    func test_hashstring_bar_returnsItsMd5() throws {
        // Given
        let hash = try subject.hash("bar")

        // Then
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2") // This is the md5 of "bar"
    }

    func test_hashstrings_foo_bar_returnsAnotherMd5() throws {
        // Given
        let hash = try subject.hash(["foo", "bar"])

        // Then
        XCTAssertEqual(hash, "3858f62230ac3c915f300c664312c63f") // This is the md5 of "foobar"
    }

    func test_hashdict_returnsMd5OfConcatenation() throws {
        // Given
        let hash = try subject.hash(["1": "foo", "2": "bar"])
        let expectedHash = try subject.hash("1:foo-2:bar")
        // Then
        XCTAssertEqual(hash, expectedHash)
    }

    func test_hashFile_hashesTheExpectedFile() async throws {
        // Given
        let path = try await writeToTemporaryPath(content: "foo")

        // When
        let hash = try await subject.hash(path: path)

        // Then
        XCTAssertEqual(hash, "acbd18db4cc2f85cedef654fccc4a4d8") // This is the md5 of "foo"
    }

    func test_hashFile_isNotHarcoded() async throws {
        // Given
        let path = try await writeToTemporaryPath(content: "bar")

        // When
        let hash = try await subject.hash(path: path)

        // Then
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2") // This is the md5 of "bar"
    }

    func test_hashFile_whenFileDoesntExist_itThrowsFileNotFound() async throws {
        // Given
        let wrongPath = try AbsolutePath(validating: "/shakirashakira")

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.hash(path: wrongPath),
            ContentHashingError.fileHashingFailed(wrongPath)
        )
    }

    func test_hash_sortedContentsOfADirectorySkippingDSStore() async throws {
        // given
        let folderPath = try temporaryPath().appending(component: "assets.xcassets")
        try await fileSystem.makeDirectory(at: folderPath)

        let files = [
            "foo": "bar",
            "foo2": "bar2",
            ".ds_store": "should be ignored",
            ".DS_STORE": "should be ignored too",
        ]

        try await writeFiles(to: folderPath, files: files)

        // When
        let hash = try await subject.hash(path: folderPath)

        // Then
        let expectedHashes = try [
            subject.hash("path-foo-content-\(subject.hash("bar"))"),
            subject.hash("path-foo2-content-\(subject.hash("bar2"))"),
        ]
        XCTAssertEqual(hash, expectedHashes.sorted().joined(separator: "-"))
    }

    func test_hash_ContentsOfADirectoryIncludingSymbolicLinksWithRelativePaths() async throws {
        // Given
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
            let destinationContentHash = try subject.hash("destination")
            let expectedHashes = try [
                subject.hash("path-destination-content-\(destinationContentHash)"),
                subject.hash("path-foo.txt-content-\(subject.hash("foo"))"),
                subject.hash("path-symbolic-content-\(destinationContentHash)"),
            ]
            XCTAssertEqual(hash, expectedHashes.sorted().joined(separator: "-"))
        }
    }

    // MARK: - Private

    private func writeToTemporaryPath(fileName: String = "foo", content: String = "foo") async throws -> AbsolutePath {
        let path = try temporaryPath().appending(component: fileName)
        try await fileSystem.writeText(content, at: path)
        return path
    }

    private func writeFiles(to folder: AbsolutePath, files: [String: String]) async throws {
        for file in files {
            let filePath = folder.appending(component: file.key)
            if try await fileSystem.exists(filePath) {
                try await fileSystem.remove(filePath)
            }
            try await fileSystem.writeText(file.value, at: filePath)
        }
    }
}
