import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class HeadersContentHasherTests: TuistUnitTestCase {
    private var subject: HeadersContentHasher!
    private var contentHasher: MockContentHashing!
    private let filePath1 = try! AbsolutePath(validating: "/file1")
    private let filePath2 = try! AbsolutePath(validating: "/file2")
    private let filePath3 = try! AbsolutePath(validating: "/file3")
    private let filePath4 = try! AbsolutePath(validating: "/file4")
    private let filePath5 = try! AbsolutePath(validating: "/file5")
    private let filePath6 = try! AbsolutePath(validating: "/file6")

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = HeadersContentHasher(contentHasher: contentHasher)

        given(contentHasher).hash(path: .value(filePath1)).willReturn("1")
        given(contentHasher).hash(path: .value(filePath2)).willReturn("2")
        given(contentHasher).hash(path: .value(filePath3)).willReturn("3")
        given(contentHasher).hash(path: .value(filePath4)).willReturn("4")
        given(contentHasher).hash(path: .value(filePath5)).willReturn("5")
        given(contentHasher).hash(path: .value(filePath6)).willReturn("6")
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    private var headers: Headers {
        Headers(
            public: [filePath1, filePath2],
            private: [filePath3, filePath4],
            project: [filePath5, filePath6]
        )
    }

    func test_hash_withLegacyBackend_preservesInputOrder() async throws {
        try await withMockedEnvironment {
            // Given
            Environment.mocked?.variables["TUIST_FILESYSTEM_BACKEND"] = "legacy"

            // When
            let hash = try await subject.hash(headers: headers)

            // Then
            XCTAssertEqual(hash, "1;2;3;4;5;6")
        }
    }

    func test_hash_withSwiftFileSystemBackend_preservesInputOrder() async throws {
        try await withMockedEnvironment {
            // Given
            Environment.mocked?.variables["TUIST_FILESYSTEM_BACKEND"] = "swift-file-system"

            // When
            let hash = try await subject.hash(headers: headers)

            // Then
            XCTAssertEqual(hash, "1;2;3;4;5;6")
        }
    }
}
