import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class ResourcesContentHasherTests: TuistUnitTestCase {
    private var subject: ResourcesContentHasher!
    private var contentHasher: MockContentHashing!
    private let filePath1 = try! AbsolutePath(validating: "/file1")
    private let filePath2 = try! AbsolutePath(validating: "/file2")

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = ResourcesContentHasher(contentHasher: contentHasher)

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

    func test_hash_callsContentHasherWithTheExpectedParameter() throws {
        // Given
        let file1 = ResourceFileElement.file(path: filePath1)
        let file2 = ResourceFileElement.file(path: filePath2)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("1")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("2")

        // When
        let hash = try subject.hash(resources: .init([file1, file2]))

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(2)
        XCTAssertEqual(hash, "1;2")
    }

    func test_hash_includesFolderReference() throws {
        // Given
        let file1 = ResourceFileElement.file(path: filePath1)
        let file2 = ResourceFileElement.folderReference(path: filePath2)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("1")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("2")

        // When
        let hash = try subject.hash(resources: .init([file1, file2]))

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(2)
        XCTAssertEqual(hash, "1;2")
    }

    func test_hash_sortsTheResourcesBeforeCalculatingTheHash() throws {
        // Given
        let file1 = ResourceFileElement.file(path: filePath1)
        let file2 = ResourceFileElement.folderReference(path: filePath2)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("1")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("2")

        // When/Then
        XCTAssertEqual(try subject.hash(resources: .init([file1, file2])), try subject.hash(resources: .init([file2, file1])))
    }

    func test_hash_hashesThePrivacyManifestToo() throws {
        // Given
        let file1 = ResourceFileElement.file(path: filePath1)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("1")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("2")
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 }

        let resources = ResourceFileElements([file1, file1], privacyManifest: PrivacyManifest(
            tracking: true,
            trackingDomains: ["io.tuist"],
            collectedDataTypes: [["test": .string("tuist")]],
            accessedApiTypes: [["test": .string("tuist")]]
        ))

        // When/Then
        XCTAssertEqual(try subject.hash(resources: resources), try subject.hash(resources: resources))
    }
}
