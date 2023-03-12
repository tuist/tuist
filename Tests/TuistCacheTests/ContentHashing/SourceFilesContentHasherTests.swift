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

final class SourceFilesContentHasherTests: TuistUnitTestCase {
    private var subject: SourceFilesContentHasher!
    private var mockContentHasher: MockContentHasher!
    private let sourceFile1Path = try! AbsolutePath(validating: "/file1")
    private let sourceFile2Path = try! AbsolutePath(validating: "/file2")
    private var sourceFile1: SourceFile!
    private var sourceFile2: SourceFile!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = SourceFilesContentHasher(contentHasher: mockContentHasher)
        sourceFile1 = SourceFile(path: sourceFile1Path, compilerFlags: "-fno-objc-arc")
        sourceFile2 = SourceFile(path: sourceFile2Path, compilerFlags: "-print-objc-runtime-info")
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        sourceFile1 = nil
        sourceFile2 = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_when_the_files_have_a_hash() throws {
        // When
        sourceFile1 = SourceFile(path: sourceFile1Path, contentHash: "first")
        sourceFile2 = SourceFile(path: sourceFile2Path, contentHash: "second")
        let hash = try subject.hash(sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(hash, "first;second")
    }

    func test_hash_returnsSameValue() throws {
        // When
        let hash = try subject.hash(sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(hash, "-fno-objc-arc-hash;-print-objc-runtime-info-hash")
    }

    func test_hash_includesFileContentHashAndCompilerFlags() throws {
        // Given
        mockContentHasher.stubHashForPath[sourceFile1Path] = "file1-content-hash"
        mockContentHasher.stubHashForPath[sourceFile2Path] = "file2-content-hash"

        // When
        _ = try subject.hash(sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(
            mockContentHasher.hashStringsSpy,
            ["file1-content-hash-fno-objc-arc-hash", "file2-content-hash-print-objc-runtime-info-hash"]
        )
    }
}
