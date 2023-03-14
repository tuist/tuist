import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class CopyFilesActionsContentHasherTests: TuistUnitTestCase {
    private var subject: CopyFilesContentHasher!
    private var contentHasher: MockContentHasher!
    private var temporaryDirectory: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        contentHasher = MockContentHasher()
        subject = CopyFilesContentHasher(contentHasher: contentHasher)
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
        files: [FileElement] = [.file(path: "/file1.ttf"), .file(path: "/file2.ttf")]
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
        contentHasher.stubHashForPath[try AbsolutePath(validating: "/file1.ttf")] = file1Hash
        contentHasher.stubHashForPath[try AbsolutePath(validating: "/file2.ttf")] = file2Hash

        // When
        _ = try subject.hash(copyFiles: [copyFilesAction])

        // Then
        let expected = [file1Hash, file2Hash, "Copy Fonts", "resources", "Fonts"]
        XCTAssertEqual(contentHasher.hashPathCallCount, 2)
        XCTAssertEqual(contentHasher.hashStringsSpy, expected)
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

        contentHasher.stubHashForPath[try AbsolutePath(validating: "/file1.template")] = file1Hash

        // When
        _ = try subject.hash(copyFiles: [copyFilesAction])

        // Then
        let expected = [file1Hash, "Copy Templates", "sharedSupport", "Templates"]
        XCTAssertEqual(contentHasher.hashPathCallCount, 1)
        XCTAssertEqual(contentHasher.hashStringsSpy, expected)
    }
}
