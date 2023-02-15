import TSCBasic
import TuistCacheTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheContentHasherTests: TuistUnitTestCase {
    private var subject: CacheContentHasher!
    private var mockContentHashing: MockContentHasher!

    override func setUp() {
        super.setUp()
        mockContentHashing = MockContentHasher()
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
        var hashedStrings: [String] = []
        mockContentHashing.hashStub = {
            hashedStrings.append($0)
            return $0
        }
        _ = try subject.hash("foo")

        // Then
        XCTAssertEqual(
            hashedStrings,
            ["foo"]
        )
    }

    func test_hashStrings_callsContentHasherWithExpectedStrings() throws {
        // When
        _ = try subject.hash(["foo", "bar"])

        // Then
        XCTAssertEqual(mockContentHashing.hashStringsCallCount, 1)
        XCTAssertEqual(mockContentHashing.hashStringsSpy, ["foo", "bar"])
    }

    func test_hashpath_callsContentHasherWithExpectedPath() throws {
        // Given
        let path = try AbsolutePath(validating: "/foo")
        mockContentHashing.stubHashForPath[path] = "foo-hash"

        // When
        _ = try subject.hash(path: path)

        // Then
        XCTAssertEqual(mockContentHashing.hashPathCallCount, 1)
        XCTAssertEqual(mockContentHashing.stubHashForPath[path], "foo-hash")
    }

    func test_hashpath_secondTime_doesntCallContentHasher() throws {
        // Given
        let path = try AbsolutePath(validating: "/foo")
        mockContentHashing.stubHashForPath[path] = "foo-hash"

        // When
        let hash = try subject.hash(path: path)
        let cachedHash = try subject.hash(path: path)

        // Then
        XCTAssertEqual(mockContentHashing.hashPathCallCount, 1)
        XCTAssertEqual(mockContentHashing.stubHashForPath[path], "foo-hash")
        XCTAssertEqual(hash, cachedHash)
    }
}
