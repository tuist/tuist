import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class CopyFilesContentHasherTests: TuistUnitTestCase {
    private var subject: CopyFilesContentHasher!
    private var contentHasher: MockContentHashing!
    private var temporaryDirectory: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = CopyFilesContentHasher(contentHasher: contentHasher)

        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }

        do {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        } catch {
            XCTFail("Error while creating temporary directory")
        }
    }

    override func tearDown() {
        subject = nil
        temporaryDirectory = nil
        contentHasher = nil

        super.tearDown()
    }

    private func makeCopyFilesAction(
        name: String = "Copy Fonts",
        destination: CopyFilesAction.Destination = .resources,
        subpath: String? = "Fonts",
        files: [CopyFileElement] = [.file(path: "/file1.ttf"), .file(path: "/file2.ttf")]
    ) -> CopyFilesAction {
        CopyFilesAction(
            name: name,
            destination: destination,
            subpath: subpath,
            files: files
        )
    }

    // MARK: - Tests

    func test_hash_copyFilesAction_callsMockHasherWithExpectedStrings() throws {
        // Given
        let file1Hash = "file1-content-hash"
        let file2Hash = "file2-content-hash"
        let copyFilesAction = makeCopyFilesAction()
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/file1.ttf")))
            .willReturn(file1Hash)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/file2.ttf")))
            .willReturn(file2Hash)

        // When
        _ = try subject.hash(copyFiles: [copyFilesAction])

        // Then
        verify(contentHasher)
            .hash(.value(["file1-content-hash", "file2-content-hash", "Copy Fonts", "resources", "Fonts"]))
            .called(1)
        verify(contentHasher)
            .hash(Parameter<[String]>.any)
            .called(1)
        verify(contentHasher)
            .hash(path: .any)
            .called(2)
    }

    func test_hash__copyFilesAction_valuesAreNotHarcoded() throws {
        // Given
        let file1Hash = "file1-content-hash"
        let copyFilesAction = makeCopyFilesAction(
            name: "Copy Templates",
            destination: .sharedSupport,
            subpath: "Templates",
            files: [.file(path: "/file1.template")]
        )

        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/file1.template")))
            .willReturn(file1Hash)

        // When
        _ = try subject.hash(copyFiles: [copyFilesAction])

        // Then
        verify(contentHasher)
            .hash(.value(["file1-content-hash", "Copy Templates", "sharedSupport", "Templates"]))
            .called(1)
        verify(contentHasher)
            .hash(Parameter<[String]>.any)
            .called(1)
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }
}
