import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import XCTest
import TuistSupport
import TuistCacheTesting
@testable import TuistCache
@testable import TuistSupportTesting

final class SourceFilesContentHasherTests: TuistUnitTestCase {
    private var sut: SourceFilesContentHasher!
    private var mockContentHasher: MockContentHashing!
    private var temporaryDirectory: TemporaryDirectory!
    private let sourceFile1Path = AbsolutePath("/file1")
    private let sourceFile2Path = AbsolutePath("/file2")
    private var sourceFile1: Target.SourceFile!
    private var sourceFile2: Target.SourceFile!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
        sut = SourceFilesContentHasher(contentHasher: mockContentHasher)
        sourceFile1 = (path: sourceFile1Path, compilerFlags: "-fno-objc-arc")
        sourceFile2 = (path: sourceFile2Path, compilerFlags: "-print-objc-runtime-info")

        do {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        } catch {
            XCTFail("Error while creating temporary directory")
        }
    }

    override func tearDown() {
        sut = nil
        temporaryDirectory = nil
        mockContentHasher = nil
        sourceFile1 = nil
        sourceFile2 = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_returnsSameValue() throws {
        mockContentHasher.hashStringsStub = "fixed"
        let hash = try sut.hash(sources: [sourceFile1, sourceFile2])
        XCTAssertEqual(hash, "fixed")
    }

    func test_hash_includesFileContentHashAndCompilerFlags() throws {
        mockContentHasher.stubHashForPath[sourceFile1Path] = "file1-content-hash"
        mockContentHasher.stubHashForPath[sourceFile2Path] = "file2-content-hash"
        mockContentHasher.hashStringStub = "-compilerflag"

        _ = try sut.hash(sources: [sourceFile1, sourceFile2])

        XCTAssertEqual(mockContentHasher.hashStringsSpy, ["file1-content-hash-compilerflag", "file2-content-hash-compilerflag"])
    }

    func test_hash_filesAreSortedByPath() throws {
        mockContentHasher.stubHashForPath[sourceFile1Path] = "file1-content-hash"
        mockContentHasher.stubHashForPath[sourceFile2Path] = "file2-content-hash"
        mockContentHasher.hashStringStub = "-compilerflag"

        _ = try sut.hash(sources: [sourceFile2, sourceFile1])

        XCTAssertEqual(mockContentHasher.hashStringsSpy, ["file1-content-hash-compilerflag", "file2-content-hash-compilerflag"])
    }
}
