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

final class HeadersContentHasherTests: TuistUnitTestCase {
    private var subject: HeadersContentHasher!
    private var mockContentHasher: MockContentHasher!
    private let filePath1 = try! AbsolutePath(validating: "/file1")
    private let filePath2 = try! AbsolutePath(validating: "/file2")
    private let filePath3 = try! AbsolutePath(validating: "/file3")
    private let filePath4 = try! AbsolutePath(validating: "/file4")
    private let filePath5 = try! AbsolutePath(validating: "/file5")
    private let filePath6 = try! AbsolutePath(validating: "/file6")

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = HeadersContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_callsContentHasherWithTheExpectedParameters() throws {
        // Given
        mockContentHasher.stubHashForPath[filePath1] = "1"
        mockContentHasher.stubHashForPath[filePath2] = "2"
        mockContentHasher.stubHashForPath[filePath3] = "3"
        mockContentHasher.stubHashForPath[filePath4] = "4"
        mockContentHasher.stubHashForPath[filePath5] = "5"
        mockContentHasher.stubHashForPath[filePath6] = "6"

        // When
        let headers = Headers(
            public: [filePath1, filePath2],
            private: [filePath3, filePath4],
            project: [filePath5, filePath6]
        )

        // Then
        let hash = try subject.hash(headers: headers)
        XCTAssertEqual(hash, "1;2;3;4;5;6")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 6)
    }
}
