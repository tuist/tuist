import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistHasher

final class CachedContentHasherTests: TuistUnitTestCase {
    private var subject: CachedContentHasher!
    private var contentHasher: MockContentHashing!

    override func setUp() {
        super.setUp()
        contentHasher = MockContentHashing()
        subject = CachedContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hashString_callsContentHasherWithExpectedString() throws {
        // Given
        given(contentHasher)
            .hash(.value("foo"))
            .willReturn("foo")

        // When
        _ = try subject.hash("foo")

        // Then
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hashStrings_callsContentHasherWithExpectedStrings() throws {
        // Given
        given(contentHasher)
            .hash(.value("foo"))
            .willReturn("foo")
        given(contentHasher)
            .hash(.value("bar"))
            .willReturn("bar")

        // When
        _ = try subject.hash(["foo", "bar"])

        // Then
        verify(contentHasher)
            .hash(Parameter<[String]>.any)
            .called(1)
    }

    func test_hashpath_callsContentHasherWithExpectedPath() throws {
        // Given
        let path = try AbsolutePath(validating: "/foo")
        given(contentHasher)
            .hash(path: .value(path))
            .willReturn("foo-hash")

        // When
        _ = try subject.hash(path: path)

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }

    func test_hashpath_secondTime_doesntCallContentHasher() throws {
        // Given
        let path = try AbsolutePath(validating: "/foo")
        given(contentHasher)
            .hash(path: .value(path))
            .willReturn("foo-hash")

        // When
        let hash = try subject.hash(path: path)
        let cachedHash = try subject.hash(path: path)

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
        XCTAssertEqual(hash, cachedHash)
    }
}
