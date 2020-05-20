import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class ContentHasherTests: TuistUnitTestCase {
    private var subject: ContentHasher!
    private var mockFileHandler: MockFileHandling!

    override func setUp() {
        super.setUp()
        mockFileHandler = MockFileHandling()
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
        XCTAssertEqual(hash, "acbd18db4cc2f85cedef654fccc4a4d8")
    }

    func test_hashstring_bar_returnsItsMd5() throws {
        // Given
        let hash = try subject.hash("bar")

        // Then
        XCTAssertEqual(hash, "37b51d194a7513e45b56f6524f2d51f2")
    }

    func test_hashstrings_foo_bar_returnsAnotherMd5() throws {
        // Given
        let hash = try subject.hash(["foo", "bar"])

        // Then
        XCTAssertEqual(hash, "3858f62230ac3c915f300c664312c63f")
    }

    func test_hashFile_hashesTheExpectedFile() throws {
        // Given
        let data = Data(repeating: 1, count: 10)
        let path = AbsolutePath("/foo")
        mockFileHandler.readFileStub = data
        mockFileHandler.existsForPathStub[path] = true

        // When
        let hash = try subject.hash(fileAtPath: path)

        // Then
        XCTAssertEqual(hash, "484c5624910e6288fad69e572a0637f7")
        XCTAssertEqual(mockFileHandler.readFileSpy, path)
    }

    func test_hashFile_isNotHarcoded() throws {
        // Given
        let data = Data(repeating: 2, count: 10)
        let path = AbsolutePath("/bar")
        mockFileHandler.readFileStub = data
        mockFileHandler.existsForPathStub[path] = true

        // When
        let hash = try subject.hash(fileAtPath: path)

        // Then
        XCTAssertEqual(hash, "0a8d20ca7c979834c6e4d486d648ce1e")
        XCTAssertEqual(mockFileHandler.readFileSpy, path)
    }

    func test_hashFile_whenFileDoesntExist_itThrowsFileNotFound() {
        // Given
        let data = Data(repeating: 2, count: 10)
        let path = AbsolutePath("/bar")
        mockFileHandler.readFileStub = data

        // When
        mockFileHandler.existsForPathStub[path] = false

        // Then
        XCTAssertThrowsError(try subject.hash(fileAtPath: path)) { error in
            XCTAssertEqual(error as? FileHandlerError, FileHandlerError.fileNotFound(path))
        }
    }

    func test_hashFile_whenFailsToReadFile_itThrowsFailedToReadFile() {
        // Given
        let data = Data(repeating: 2, count: 10)
        let path = AbsolutePath("/bar")
        mockFileHandler.readFileStub = data

        // When
        mockFileHandler.existsForPathStub[path] = false

        // Then
        XCTAssertThrowsError(try subject.hash(fileAtPath: path)) { error in
            XCTAssertEqual(error as? FileHandlerError, FileHandlerError.fileNotFound(path))
        }
    }
}
