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

final class TargetScriptsContentHasherTests: TuistUnitTestCase {
    private var subject: TargetScriptsContentHasher!
    private var mockContentHasher: MockContentHasher!
    private var temporaryDirectory: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = TargetScriptsContentHasher(contentHasher: mockContentHasher)
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

    private func makeTargetScript(
        name: String = "1",
        order: TargetScript.Order = .pre,
        tool: String = "tool1",
        arguments: [String] = ["arg1", "arg2"],
        inputPaths: [AbsolutePath] = [try! AbsolutePath(validating: "/inputPaths1")],
        inputFileListPaths: [AbsolutePath] = [try! AbsolutePath(validating: "/inputFileListPaths1")],
        outputPaths: [AbsolutePath] = [try! AbsolutePath(validating: "/outputPaths1")],
        outputFileListPaths: [AbsolutePath] = [try! AbsolutePath(validating: "/outputFileListPaths1")],
        dependencyFile: AbsolutePath = try! AbsolutePath(validating: "/dependencyFile1")
    ) -> TargetScript {
        TargetScript(
            name: name,
            order: order,
            script: .tool(path: tool, args: arguments),
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            dependencyFile: dependencyFile
        )
    }

    // MARK: - Tests

    func test_hash_targetAction_withBuildVariables_callsMockHasherWithOnlyPathWithoutBuildVariable() throws {
        // Given
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputFileListPaths1")] = inputFileListPaths1
        let targetScript = makeTargetScript(
            inputPaths: [try AbsolutePath(validating: "/$(SRCROOT)/inputPaths1")],
            inputFileListPaths: [try AbsolutePath(validating: "/inputFileListPaths1")],
            outputPaths: [try AbsolutePath(validating: "/$(DERIVED_FILE_DIR)/outputPaths1")],
            outputFileListPaths: [try AbsolutePath(validating: "/outputFileListPaths1")],
            dependencyFile: try AbsolutePath(validating: "/$(DERIVED_FILE_DIR)/file.d")
        )

        // When
        _ = try subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then
        let expected = [
            "$(SRCROOT)/inputPaths1",
            "$(DERIVED_FILE_DIR)/file.d",
            inputFileListPaths1,
            "$(DERIVED_FILE_DIR)/outputPaths1",
            "outputFileListPaths1",
            "1",
            "tool1",
            "pre",
            "arg1",
            "arg2",
        ]

        XCTAssertPrinterOutputContains(
            "The path of the file 'inputPaths1' is hashed, not the content. Because it has a build variable."
        )
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }

    func test_hash_targetAction_callsMockHasherWithExpectedStrings() throws {
        // Given
        let inputPaths1Hash = "inputPaths1-hash"
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        let dependencyFileHash = "dependencyFile1-hash"
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputPaths1")] = inputPaths1Hash
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputFileListPaths1")] = inputFileListPaths1
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/dependencyFile1")] = dependencyFileHash
        let targetScript = makeTargetScript()

        // When
        _ = try subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then
        let expected = [
            inputPaths1Hash,
            inputFileListPaths1,
            dependencyFileHash,
            "outputPaths1",
            "outputFileListPaths1",
            "1",
            "tool1",
            "pre",
            "arg1",
            "arg2",
        ]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }

    func test_hash_targetAction_when_path_nil_callsMockHasherWithExpectedStrings() throws {
        // Given
        let inputPaths1Hash = "inputPaths1-hash"
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        let dependencyFileHash = "dependencyFile1-hash"
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputPaths1")] = inputPaths1Hash
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputFileListPaths1")] = inputFileListPaths1
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/dependencyFile1")] = dependencyFileHash

        let targetScript = makeTargetScript()

        // When
        _ = try subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then
        let expected = [
            inputPaths1Hash,
            inputFileListPaths1,
            dependencyFileHash,
            "outputPaths1",
            "outputFileListPaths1",
            "1",
            "tool1",
            "pre",
            "arg1",
            "arg2",
        ]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }

    func test_hash_targetAction_valuesAreNotHarcoded() throws {
        // Given
        let inputPaths2Hash = "inputPaths2-hash"
        let inputFileListPaths2 = "inputFileListPaths2-hash"
        let dependencyFileHash = "/dependencyFilePath4-hash"
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputPaths2")] = inputPaths2Hash
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/inputFileListPaths2")] = inputFileListPaths2
        mockContentHasher.stubHashForPath[try AbsolutePath(validating: "/dependencyFilePath4")] = dependencyFileHash

        let targetScript = makeTargetScript(
            name: "2",
            order: .post,
            tool: "tool2",
            inputPaths: [try AbsolutePath(validating: "/inputPaths2")],
            inputFileListPaths: [try AbsolutePath(validating: "/inputFileListPaths2")],
            outputPaths: [try AbsolutePath(validating: "/outputPaths2")],
            outputFileListPaths: [try AbsolutePath(validating: "/outputFileListPaths2")],
            dependencyFile: try AbsolutePath(validating: "/dependencyFilePath4")
        )

        // When
        _ = try subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then
        let expected = [
            inputPaths2Hash,
            inputFileListPaths2,
            dependencyFileHash,
            "outputPaths2",
            "outputFileListPaths2",
            "2",
            "tool2",
            "post",
            "arg1",
            "arg2",
        ]
        XCTAssertEqual(mockContentHasher.hashStringsSpy, expected)
    }
}
