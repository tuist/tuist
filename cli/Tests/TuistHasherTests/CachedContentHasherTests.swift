import Mockable
import Path
import TuistCore
import TuistSupport
import TuistTesting
import Testing

@testable import TuistHasher

struct CachedContentHasherTests {
    private let subject: CachedContentHasher
    private let contentHasher: MockContentHashing
    init() {
        contentHasher = MockContentHashing()
        subject = CachedContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }


    // MARK: - Tests

    @Test
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

    @Test
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

    @Test
    func test_hashpath_callsContentHasherWithExpectedPath() async throws {
        // Given
        let path = try AbsolutePath(validating: "/foo")
        given(contentHasher)
            .hash(path: .value(path))
            .willReturn("foo-hash")

        // When
        _ = try await subject.hash(path: path)

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }

    @Test
    func test_hashpath_secondTime_doesntCallContentHasher() async throws {
        // Given
        let path = try AbsolutePath(validating: "/foo")
        given(contentHasher)
            .hash(path: .value(path))
            .willReturn("foo-hash")

        // When
        let hash = try await subject.hash(path: path)
        let cachedHash = try await subject.hash(path: path)

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
        #expect(hash == cachedHash)
    }
}
