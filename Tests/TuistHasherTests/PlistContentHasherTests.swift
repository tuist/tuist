import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class InfoPlistContentHasherTests: TuistUnitTestCase {
    private var subject: PlistContentHasher!
    private var contentHasher: MockContentHashing!
    private let filePath1 = try! AbsolutePath(validating: "/file1")

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = PlistContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    func test_hash_whenPlistIsFile_tellsContentHasherToHashFileContent() throws {
        // Given
        let infoPlist = InfoPlist.file(path: filePath1)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("stubHash")

        // When
        let hash = try subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
        XCTAssertEqual(hash, "stubHash")
    }

    func test_hash_whenPlistIsGeneratedFile_tellsContentHasherToHashFileContent() throws {
        // Given
        let infoPlist = InfoPlist.generatedFile(
            path: filePath1,
            data: try XCTUnwrap(Data(base64Encoded: "stubHash"))
        )
        given(contentHasher)
            .hash(Parameter<Data>.any)
            .willProduce { $0.base64EncodedString() + "-hash" }

        // When
        let hash = try subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(Parameter<Data>.any)
            .called(1)
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
        let hash = try subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
        XCTAssertEqual(
            hash,
            "1=integer(23);2=string(\"foo\");3=boolean(true);4=boolean(false);5=array([XcodeGraph.Plist.Value.string(\"5a\"), XcodeGraph.Plist.Value.string(\"5b\")]);6=dictionary([\"6a\": XcodeGraph.Plist.Value.string(\"6value\")]);-hash"
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
        let hash = try subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
        XCTAssertEqual(
            hash,
            "1=integer(23);2=string(\"foo\");3=boolean(true);4=boolean(false);5=array([XcodeGraph.Plist.Value.string(\"5a\"), XcodeGraph.Plist.Value.string(\"5b\")]);6=dictionary([\"6a\": XcodeGraph.Plist.Value.string(\"6value\")]);-hash"
        )
    }
}
