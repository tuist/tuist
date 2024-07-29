import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class SourceFilesContentHasherTests: TuistUnitTestCase {
    private var subject: SourceFilesContentHasher!
    private var contentHasher: MockContentHashing!
    private let sourceFile1Path = try! AbsolutePath(validating: "/file1")
    private let sourceFile2Path = try! AbsolutePath(validating: "/file2")
    private var sourceFile1: SourceFile!
    private var sourceFile2: SourceFile!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = SourceFilesContentHasher(contentHasher: contentHasher)
        sourceFile1 = SourceFile(path: sourceFile1Path, compilerFlags: "-fno-objc-arc")
        sourceFile2 = SourceFile(path: sourceFile2Path, compilerFlags: "-print-objc-runtime-info")

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
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
        given(contentHasher)
            .hash(path: .value(sourceFile1Path))
            .willReturn("")
        given(contentHasher)
            .hash(path: .value(sourceFile2Path))
            .willReturn("")
        let hash = try subject.hash(sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(hash, "-fno-objc-arc-hash;-print-objc-runtime-info-hash")
    }

    func test_hash_includesFileContentHashAndCompilerFlags() throws {
        // Given
        given(contentHasher)
            .hash(path: .value(sourceFile1Path))
            .willReturn("file1-content-hash")
        given(contentHasher)
            .hash(path: .value(sourceFile2Path))
            .willReturn("file2-content-hash")

        // When
        let hash = try subject.hash(sources: [sourceFile1, sourceFile2])

        // Then
        XCTAssertEqual(hash, "file1-content-hash-fno-objc-arc-hash;file2-content-hash-print-objc-runtime-info-hash")
    }
}
