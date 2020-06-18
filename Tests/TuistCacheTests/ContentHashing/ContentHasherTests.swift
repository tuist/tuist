import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCache
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
        let hash = try subject.hash(fileAtPath: path)

        // Then
        XCTAssertEqual(hash, "acbd18db4cc2f85cedef654fccc4a4d8") // This is the md5 of "foo"
    }

    func test_hashFile_isNotHarcoded() throws {
        // Given
        let path = try writeToTemporaryPath(content: "bar")

        // When
        let hash = try subject.hash(fileAtPath: path)

        // Then
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2") // This is the md5 of "bar"
    }

    func test_hashFile_whenFileDoesntExist_itThrowsFileNotFound() {
        // Given
        let wrongPath = AbsolutePath("/shakirashakira")

        // Then
        XCTAssertThrowsError(try subject.hash(fileAtPath: wrongPath)) { error in
            XCTAssertEqual(error as? FileHandlerError, FileHandlerError.fileNotFound(wrongPath))
        }
    }

    // MARK: - Private

    private func writeToTemporaryPath(fileName: String = "foo", content: String = "foo") throws -> AbsolutePath {
        let path = try temporaryPath().appending(component: fileName)
        try mockFileHandler.write(content, path: path, atomically: true)
        return path
    }
}
