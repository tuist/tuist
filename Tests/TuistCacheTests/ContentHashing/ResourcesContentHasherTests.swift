import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class ResourcesContentHasherTests: TuistUnitTestCase {
    private var subject: ResourcesContentHasher!
    private var mockContentHasher: MockContentHashing!
    private let filePath1 = AbsolutePath("/file1")
    private let filePath2 = AbsolutePath("/file2")

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
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
        let hash = try subject.hash(resources: [file1, file2])

        // Then
        XCTAssertEqual(mockContentHasher.hashFileAtPathCallCount, 2)
        XCTAssertEqual(hash, "1;2")
    }

    func test_hash_includesFolderReference() throws {
        // Given
        let file1 = FileElement.file(path: filePath1)
        let file2 = FileElement.folderReference(path: filePath2)
        mockContentHasher.stubHashForPath[filePath1] = "1"
        mockContentHasher.stubHashForPath[filePath2] = "2"

        // When
        let hash = try subject.hash(resources: [file1, file2])

        // Then
        XCTAssertEqual(mockContentHasher.hashFileAtPathCallCount, 2)
        XCTAssertEqual(hash, "1;2")
    }
}
