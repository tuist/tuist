import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class TargetActionsContentHasherTests: TuistUnitTestCase {
    private var subject: TargetActionsContentHasher!
    private var mockContentHasher: MockContentHashing!
    private var temporaryDirectory: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
        subject = TargetActionsContentHasher(contentHasher: mockContentHasher)
        do {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        } catch {
            XCTFail("Error while creating temporary directory")
        }
    }

    override func tearDown() {
        subject = nil
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
                                  outputFileListPaths: [AbsolutePath] = [AbsolutePath("/outputFileListPaths1")]) -> TargetAction
    {
        TargetAction(name: name,
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
        // Given
        let file1hash = "file1-content-hash"
        let inputPaths1Hash = "inputPaths1-hash"
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        let outputPaths1 = "outputPaths1-hash"
        let outputFileListPaths1 = "outputFileListPaths1-hash"
        mockContentHasher.stubHashForPath[AbsolutePath("/path1")] = file1hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputPaths1")] = inputPaths1Hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputFileListPaths1")] = inputFileListPaths1
        mockContentHasher.stubHashForPath[AbsolutePath("/outputPaths1")] = outputPaths1
        mockContentHasher.stubHashForPath[AbsolutePath("/outputFileListPaths1")] = outputFileListPaths1
        let targetAction = makeTargetAction()

        // When
        _ = try subject.hash(targetActions: [targetAction])

        // Then
        let expected = [file1hash,
                        inputPaths1Hash,
                        inputFileListPaths1,
                        outputPaths1,
                        outputFileListPaths1,
                        "1",
                        "tool1",
                        "pre",
                        "arg1",
                        "arg2"]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }

    func test_hash_targetAction_valuesAreNotHarcoded() throws {
        // Given
        let file2hash = "file2-content-hash"
        let inputPaths2Hash = "inputPaths2-hash"
        let inputFileListPaths2 = "inputFileListPaths2-hash"
        let outputPaths2 = "outputPaths2-hash"
        let outputFileListPaths2 = "outputFileListPaths2-hash"
        mockContentHasher.stubHashForPath[AbsolutePath("/path2")] = file2hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputPaths2")] = inputPaths2Hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputFileListPaths2")] = inputFileListPaths2
        mockContentHasher.stubHashForPath[AbsolutePath("/outputPaths2")] = outputPaths2
        mockContentHasher.stubHashForPath[AbsolutePath("/outputFileListPaths2")] = outputFileListPaths2
        let targetAction = makeTargetAction(name: "2",
                                            order: .post,
                                            tool: "tool2",
                                            path: AbsolutePath("/path2"),
                                            inputPaths: [AbsolutePath("/inputPaths2")],
                                            inputFileListPaths: [AbsolutePath("/inputFileListPaths2")],
                                            outputPaths: [AbsolutePath("/outputPaths2")],
                                            outputFileListPaths: [AbsolutePath("/outputFileListPaths2")])

        // When
        _ = try subject.hash(targetActions: [targetAction])

        // Then
        let expected = [file2hash,
                        inputPaths2Hash,
                        inputFileListPaths2,
                        outputPaths2,
                        outputFileListPaths2,
                        "2",
                        "tool2",
                        "post",
                        "arg1", "arg2"]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }
}
