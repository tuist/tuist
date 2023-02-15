import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class ContentHasherTests: TuistUnitTestCase {
    private var subject: ContentHasher!
    private var mockFileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        mockFileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        subject = ContentHasher(fileHandler: mockFileHandler)
    }

    override func tearDown() {
        subject = nil
        mockFileHandler = nil
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

    func test_hashFile_hashesTheExpectedFile() throws {
        // Given
        let path = try writeToTemporaryPath(content: "foo")

        // When
        let hash = try subject.hash(path: path)

        // Then
        XCTAssertEqual(hash, "acbd18db4cc2f85cedef654fccc4a4d8") // This is the md5 of "foo"
    }

    func test_hashFile_isNotHarcoded() throws {
        // Given
        let path = try writeToTemporaryPath(content: "bar")

        // When
        let hash = try subject.hash(path: path)

        // Then
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2") // This is the md5 of "bar"
    }

    func test_hashFile_whenFileDoesntExist_itThrowsFileNotFound() throws {
        // Given
        let wrongPath = try AbsolutePath(validating: "/shakirashakira")

        // Then
        XCTAssertThrowsError(try subject.hash(path: wrongPath)) { error in
            XCTAssertEqual(error as? FileHandlerError, FileHandlerError.fileNotFound(wrongPath))
        }
    }

    func test_hash_sortedContentsOfADirectorySkippingDSStore() throws {
        // given
        let folderPath = try temporaryPath().appending(component: "assets.xcassets")
        try mockFileHandler.createFolder(folderPath)

        let files = [
            "foo": "bar",
            "foo2": "bar2",
            ".ds_store": "should be ignored",
            ".DS_STORE": "should be ignored too",
        ]

        try writeFiles(to: folderPath, files: files)

        // When
        let hash = try subject.hash(path: folderPath)

        // Then
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2-224e2539f52203eb33728acd228b4432")
        // This is the md5 of "bar", a dash, md5 of "bar2", in sorted order according to the file name
        // and .DS_STORE should be ignored
    }

    // MARK: - Private

    private func writeToTemporaryPath(fileName: String = "foo", content: String = "foo") throws -> AbsolutePath {
        let path = try temporaryPath().appending(component: fileName)
        try mockFileHandler.write(content, path: path, atomically: true)
        return path
    }

    private func writeFiles(to folder: AbsolutePath, files: [String: String]) throws {
        try files.forEach {
            try mockFileHandler.write($0.value, path: folder.appending(component: $0.key), atomically: true)
        }
    }
}
