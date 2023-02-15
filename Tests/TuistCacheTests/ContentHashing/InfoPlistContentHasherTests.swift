import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class InfoPlistContentHasherTests: TuistUnitTestCase {
    private var subject: InfoPlistContentHasher!
    private var mockContentHasher: MockContentHasher!
    private let filePath1 = try! AbsolutePath(validating: "/file1")

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = InfoPlistContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_whenPlistIsFile_tellsContentHasherToHashFileContent() throws {
        // Given
        let infoPlist = InfoPlist.file(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "stubHash"

        // When
        let hash = try subject.hash(plist: infoPlist)

        // Then
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
        XCTAssertEqual(hash, "stubHash")
    }

    func test_hash_whenPlistIsGeneratedFile_tellsContentHasherToHashFileContent() throws {
        // Given
        let infoPlist = InfoPlist.generatedFile(
            path: filePath1,
            data: try XCTUnwrap(Data(base64Encoded: "stubHash"))
        )

        // When
        let hash = try subject.hash(plist: infoPlist)

        // Then
        XCTAssertEqual(mockContentHasher.hashDataCallCount, 1)
        XCTAssertEqual(hash, "stubHash-hash")
    }

    func test_hash_whenPlistIsDictionary_allDictionaryValuesAreConsideredForHash() throws {
        // Given
        let infoPlist = InfoPlist.dictionary([
            "1": 23,
            "2": "foo",
            "3": true,
            "4": false,
            "5": ["5a", "5b"],
            "6": ["6a": "6value"],
        ])
        // When
        let hash = try subject.hash(plist: infoPlist)

        // Then
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
        XCTAssertEqual(
            hash,
            "1=integer(23);2=string(\"foo\");3=boolean(true);4=boolean(false);5=array([TuistGraph.InfoPlist.Value.string(\"5a\"), TuistGraph.InfoPlist.Value.string(\"5b\")]);6=dictionary([\"6a\": TuistGraph.InfoPlist.Value.string(\"6value\")]);-hash"
        )
    }

    func test_hash_whenPlistIsExtendingDefault_allDictionaryValuesAreConsideredForHash() throws {
        // Given
        let infoPlist = InfoPlist.extendingDefault(with: [
            "1": 23,
            "2": "foo",
            "3": true,
            "4": false,
            "5": ["5a", "5b"],
            "6": ["6a": "6value"],
        ])

        // When
        let hash = try subject.hash(plist: infoPlist)

        // Then
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
        XCTAssertEqual(
            hash,
            "1=integer(23);2=string(\"foo\");3=boolean(true);4=boolean(false);5=array([TuistGraph.InfoPlist.Value.string(\"5a\"), TuistGraph.InfoPlist.Value.string(\"5b\")]);6=dictionary([\"6a\": TuistGraph.InfoPlist.Value.string(\"6value\")]);-hash"
        )
    }
}
