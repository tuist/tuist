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
        inputPaths: [AbsolutePath] = [AbsolutePath("/inputPaths1")],
        inputFileListPaths: [AbsolutePath] = [AbsolutePath("/inputFileListPaths1")],
        outputPaths: [AbsolutePath] = [AbsolutePath("/outputPaths1")],
        outputFileListPaths: [AbsolutePath] = [AbsolutePath("/outputFileListPaths1")],
        dependencyFile: AbsolutePath = AbsolutePath("/dependencyFile1")
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
        mockContentHasher.stubHashForPath[AbsolutePath("/inputFileListPaths1")] = inputFileListPaths1
        let targetScript = makeTargetScript(
            inputPaths: [AbsolutePath("/$(SRCROOT)/inputPaths1")],
            inputFileListPaths: [AbsolutePath("/inputFileListPaths1")],
            outputPaths: [AbsolutePath("/$(DERIVED_FILE_DIR)/outputPaths1")],
            outputFileListPaths: [AbsolutePath("/outputFileListPaths1")],
            dependencyFile: AbsolutePath("/$(DERIVED_FILE_DIR)/file.d")
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
        mockContentHasher.stubHashForPath[AbsolutePath("/inputPaths1")] = inputPaths1Hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputFileListPaths1")] = inputFileListPaths1
        mockContentHasher.stubHashForPath[AbsolutePath("/dependencyFile1")] = dependencyFileHash
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
        mockContentHasher.stubHashForPath[AbsolutePath("/inputPaths1")] = inputPaths1Hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputFileListPaths1")] = inputFileListPaths1
        mockContentHasher.stubHashForPath[AbsolutePath("/dependencyFile1")] = dependencyFileHash

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
        mockContentHasher.stubHashForPath[AbsolutePath("/inputPaths2")] = inputPaths2Hash
        mockContentHasher.stubHashForPath[AbsolutePath("/inputFileListPaths2")] = inputFileListPaths2
        mockContentHasher.stubHashForPath[AbsolutePath("/dependencyFilePath4")] = dependencyFileHash

        let targetScript = makeTargetScript(
            name: "2",
            order: .post,
            tool: "tool2",
            inputPaths: [AbsolutePath("/inputPaths2")],
            inputFileListPaths: [AbsolutePath("/inputFileListPaths2")],
            outputPaths: [AbsolutePath("/outputPaths2")],
            outputFileListPaths: [AbsolutePath("/outputFileListPaths2")],
            dependencyFile: AbsolutePath("/dependencyFilePath4")
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
