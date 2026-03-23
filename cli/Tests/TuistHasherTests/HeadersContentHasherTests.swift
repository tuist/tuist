import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import Testing

@testable import TuistHasher

struct HeadersContentHasherTests {
    private let subject: HeadersContentHasher
    private let contentHasher: MockContentHashing
    private let filePath1 = try! AbsolutePath(validating: "/file1")
    private let filePath2 = try! AbsolutePath(validating: "/file2")
    private let filePath3 = try! AbsolutePath(validating: "/file3")
    private let filePath4 = try! AbsolutePath(validating: "/file4")
    private let filePath5 = try! AbsolutePath(validating: "/file5")
    private let filePath6 = try! AbsolutePath(validating: "/file6")

    init() {
        contentHasher = .init()
        subject = HeadersContentHasher(contentHasher: contentHasher)
    }


    @Test
    func test_hash_callsContentHasherWithTheExpectedParameters() async throws {
        // Given
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("1")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("2")
        given(contentHasher)
            .hash(path: .value(filePath3))
            .willReturn("3")
        given(contentHasher)
            .hash(path: .value(filePath4))
            .willReturn("4")
        given(contentHasher)
            .hash(path: .value(filePath5))
            .willReturn("5")
        given(contentHasher)
            .hash(path: .value(filePath6))
            .willReturn("6")
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }

        // When
        let headers = Headers(
            public: [filePath1, filePath2],
            private: [filePath3, filePath4],
            project: [filePath5, filePath6]
        )

        // Then
        let hash = try await subject.hash(headers: headers)
        #expect(hash == "1;2;3;4;5;6")
        verify(contentHasher)
            .hash(path: .any)
            .called(6)
    }
}
