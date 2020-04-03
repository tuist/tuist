import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import XCTest
import TuistSupport
import TuistCacheTesting
@testable import TuistCache
@testable import TuistSupportTesting

final class TargetActionsContentHasherTests: TuistUnitTestCase {
    private var sut: TargetActionsContentHasher!
    private var mockContentHasher: MockContentHashing!
    private var temporaryDirectory: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
        sut = TargetActionsContentHasher(contentHasher: mockContentHasher)
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

        super.tearDown()
    }

    private func makeTargetAction(name: String = "1",
                                  order: TargetAction.Order = .pre,
                                  tool: String = "tool1",
                                  path: AbsolutePath = AbsolutePath("/path1"),
                                  arguments: [String] = ["arg1", "arg2"],
                                  inputPaths: [AbsolutePath] = [AbsolutePath("/inputPaths1")],
                                  inputFileListPaths: [AbsolutePath] = [AbsolutePath("/inputFileListPaths1")],
                                  outputPaths: [AbsolutePath] = [AbsolutePath("/outputPaths1")],
                                  outputFileListPaths: [AbsolutePath] = [AbsolutePath("/outputFileListPaths1")]) -> TargetAction {
        return TargetAction(name: name,
                            order: order,
                            tool: tool,
                            path: path,
                            arguments: arguments,
                            inputPaths: inputPaths,
                            inputFileListPaths: inputFileListPaths,
                            outputPaths: outputPaths,
                            outputFileListPaths: outputFileListPaths)
    }

    // MARK: - Tests

    func test_hash_targetAction_callsMockHasherWithExpectedStrings() throws {
        let file1hash = "file1-content-hash"
        mockContentHasher.stubHashForPath[AbsolutePath("/path1")] = file1hash

        let targetAction = makeTargetAction()
        _ = try sut.hash(targetActions: [targetAction])

        let expected = [file1hash,
                        "1",
                        "tool1",
                        "pre",
                        "arg1",
                        "arg2",
                        "/inputPaths1",
                        "/inputFileListPaths1",
                        "/outputPaths1",
                        "/outputFileListPaths1"]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }

    func test_hash_targetAction_valuesAreNotHarcoded() throws {
        let file2hash = "file2-content-hash"
        mockContentHasher.stubHashForPath[AbsolutePath("/path2")] = file2hash

        let targetAction = makeTargetAction(name: "2",
                                            order: .post,
                                            tool: "tool2",
                                            path: AbsolutePath("/path2"),
                                            inputPaths: [AbsolutePath("/inputPaths2a"), AbsolutePath("/inputPaths2b")],
                                            inputFileListPaths: [AbsolutePath("/inputFileListPaths2a"), AbsolutePath("/inputFileListPaths2b")],
                                            outputPaths: [AbsolutePath("/outputPaths2a"), AbsolutePath("/outputPaths2b")],
                                            outputFileListPaths: [AbsolutePath("/outputFileListPaths2a"), AbsolutePath("/outputFileListPaths2b")])

        _ = try sut.hash(targetActions: [targetAction])

        let expected = [file2hash,
                        "2",
                        "tool2",
                        "post",
                        "arg1",
                        "arg2",
                        "/inputPaths2a", "/inputPaths2b",
                        "/inputFileListPaths2a", "/inputFileListPaths2b",
                        "/outputPaths2a", "/outputPaths2b",
                        "/outputFileListPaths2a", "/outputFileListPaths2b"]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }
}
