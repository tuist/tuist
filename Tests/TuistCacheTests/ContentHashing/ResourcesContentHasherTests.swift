import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class ResourcesContentHasherTests: TuistUnitTestCase {
    private var subject: ResourcesContentHasher!
    private var mockContentHasher: MockContentHasher!
    private let filePath1 = AbsolutePath("/Briochify/file1")
    private let filePath2 = AbsolutePath("/Briochify/file2")
    private let filePath3 = AbsolutePath("/Briochify/more-resources/file3")
    private let filePath4 = AbsolutePath("/file4")
    private let sourceRootPath = AbsolutePath("/Briochify")

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = ResourcesContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_callsContentHasherWithTheExpectedParameter() throws {
        // Given
        let file1 = FileElement.file(path: filePath1)
        let file2 = FileElement.file(path: filePath2)
        mockContentHasher.stubHashForPath[filePath1] = "1"
        mockContentHasher.stubHashForPath[filePath2] = "2"

        // When
        let hash = try subject.hash(resources: [file1, file2], sourceRootPath: sourceRootPath)

        // Then
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 2)
        XCTAssertEqual(hash, "file1-hash:1;file2-hash:2")
    }

    func test_hash_includesFolderReference() throws {
        // Given
        let file1 = FileElement.file(path: filePath1)
        let file2 = FileElement.folderReference(path: filePath2)
        mockContentHasher.stubHashForPath[filePath1] = "1"
        mockContentHasher.stubHashForPath[filePath2] = "2"

        // When
        let hash = try subject.hash(resources: [file1, file2], sourceRootPath: sourceRootPath)

        // Then
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 2)
        XCTAssertEqual(hash, "file1-hash:1;file2-hash:2")
    }

    func test_hash_sortsTheResourcesBeforeCalculatingTheHash() throws {
        // Given
        let file1 = FileElement.file(path: filePath1)
        let file2 = FileElement.folderReference(path: filePath2)
        mockContentHasher.stubHashForPath[filePath1] = "1"
        mockContentHasher.stubHashForPath[filePath2] = "2"

        // When/Then
        XCTAssertEqual(try subject.hash(resources: [file1, file2], sourceRootPath: sourceRootPath), try subject.hash(resources: [file2, file1], sourceRootPath: sourceRootPath))
    }

    func test_hash_nameAlsoCalculatedNotOnlyContent() throws {
        // Given
        let file1 = FileElement.file(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "1"

        // When
        let hash = try subject.hash(resources: [file1], sourceRootPath: sourceRootPath)

        // Then
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
        XCTAssertEqual(hash, "file1-hash:1")
    }

    func test_hash_relativePathUsedNotAbsolute() throws {
        // Given
        let file1 = FileElement.file(path: filePath1)
        let file3 = FileElement.file(path: filePath3)
        let file4 = FileElement.file(path: filePath4)
        mockContentHasher.stubHashForPath[filePath1] = "1"
        mockContentHasher.stubHashForPath[filePath3] = "3"
        mockContentHasher.stubHashForPath[filePath4] = "4"

        // When
        let hash = try subject.hash(resources: [file1, file3, file4], sourceRootPath: sourceRootPath)

        // Then
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 3)
        XCTAssertEqual(hash, "file1-hash:1;more-resources/file3-hash:3;../file4-hash:4")
    }
}
