import Basic
import XCTest
import TuistSupport
import TuistCacheTesting
@testable import TuistSupportTesting
@testable import TuistCache

final class CacheContentHasherTests: TuistUnitTestCase {
    private var subject: CacheContentHasher!
    private var mockContentHashing: MockContentHashing!

    override func setUp() {
        super.setUp()
        mockContentHashing = MockContentHashing()
        subject = CacheContentHasher(contentHasher: mockContentHashing)
    }

    override func tearDown() {
        subject = nil
        mockContentHashing = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hashString_callsContentHasherWithExpectedString() throws {
        // When
        _ = try subject.hash("foo")

        // Then
        XCTAssertEqual(mockContentHashing.hashStringCallCount, 1)
        XCTAssertEqual(mockContentHashing.hashStringSpy, "foo")
    }

    func test_hashString_secondTime_doesntCallContentHasher() throws {
        // When
        let hash = try subject.hash("foo")
        let cachedHash = try subject.hash("foo")

        // Then
        XCTAssertEqual(mockContentHashing.hashStringCallCount, 1)
        XCTAssertEqual(mockContentHashing.hashStringSpy, "foo")
        XCTAssertEqual(hash, cachedHash)
    }

    func test_hashStrings_callsContentHasherWithExpectedStrings() throws {
        // When
        _ = try subject.hash(["foo", "bar"])

        // Then
        XCTAssertEqual(mockContentHashing.hashStringsCallCount, 1)
        XCTAssertEqual(mockContentHashing.hashStringsSpy, ["foo", "bar"])
    }

    func test_hashStrings_secondTime_doesntCallContentHasher() throws {
        // When
        let hash = try subject.hash(["foo", "bar"])
        let cachedHash = try subject.hash(["foo", "bar"])

        // Then
        XCTAssertEqual(mockContentHashing.hashStringsCallCount, 1)
        XCTAssertEqual(mockContentHashing.hashStringsSpy,  ["foo", "bar"])
        XCTAssertEqual(hash, cachedHash)
    }

    func test_hashFileAtPath_callsContentHasherWithExpectedPath() throws {
        // Given
        let path = AbsolutePath("/foo")
        mockContentHashing.stubHashForPath[path] = "foo-hash"

        // When
        _ = try subject.hash(fileAtPath: path)

        // Then
        XCTAssertEqual(mockContentHashing.hashFileAtPathCallCount, 1)
        XCTAssertEqual(mockContentHashing.stubHashForPath[path], "foo-hash")
    }

    func test_hashFileAtPath_secondTime_doesntCallContentHasher() throws {
        // Given
        let path = AbsolutePath("/foo")
        mockContentHashing.stubHashForPath[path] = "foo-hash"

        // When
        let hash = try subject.hash(fileAtPath: path)
        let cachedHash = try subject.hash(fileAtPath: path)

        // Then
        XCTAssertEqual(mockContentHashing.hashFileAtPathCallCount, 1)
        XCTAssertEqual(mockContentHashing.stubHashForPath[path], "foo-hash")
        XCTAssertEqual(hash, cachedHash)
    }
}
