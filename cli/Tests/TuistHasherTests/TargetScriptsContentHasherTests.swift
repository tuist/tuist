import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistHasher

struct TargetScriptsContentHasherTests {
    private let subject: TargetScriptsContentHasher
    private let contentHasher: MockContentHashing
    private let temporaryDirectory: TemporaryDirectory
    init() throws {
        contentHasher = .init()
        subject = TargetScriptsContentHasher(contentHasher: contentHasher)
        temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }

    private func makeTargetScript(
        name: String = "1",
        order: TargetScript.Order = .pre,
        tool: String = "tool1",
        arguments: [String] = ["arg1", "arg2"],
        inputPaths: [String] = ["/inputPaths1"],
        inputFileListPaths: [String] = ["/inputFileListPaths1"],
        outputPaths: [String] = ["/outputPaths1"],
        outputFileListPaths: [String] = ["/outputFileListPaths1"],
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

    @Test
    func hash_targetAction_withBuildVariables_callsMockHasherWithOnlyPathWithoutBuildVariable() async throws {
        // Given
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputFileListPaths1")))
            .willReturn(inputFileListPaths1)

        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths1")))
            .willReturn("inputPaths1-hash")

        let targetScript = TargetScript(
            name: "1",
            order: .pre,
            script: .tool(path: "tool1", args: ["arg1", "arg2"]),
            inputPaths: ["/$(SRCROOT)/inputPaths1"],
            inputFileListPaths: ["/inputFileListPaths1"],
            outputPaths: ["/$(DERIVED_FILE_DIR)/outputPaths1"],
            outputFileListPaths: ["/outputFileListPaths1"],
            dependencyFile: try AbsolutePath(validating: "/$(DERIVED_FILE_DIR)/file.d")
        )

        // When
        _ = try await subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then
        let expected = [
            "$(DERIVED_FILE_DIR)/file.d",
            "inputFileListPaths1-hash",
            "inputPaths1-hash",
            "$(DERIVED_FILE_DIR)/outputPaths1",
            "outputFileListPaths1",
            "1",
            "tool1",
            "pre",
            "arg1",
            "arg2",
        ]

        verify(contentHasher)
            .hash(.value(expected))
            .called(1)
    }

    @Test
    func hash_targetAction_callsMockHasherWithExpectedStrings() async throws {
        // Given
        let inputPaths1Hash = "inputPaths1-hash"
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        let dependencyFileHash = "dependencyFile1-hash"
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths1")))
            .willReturn(inputPaths1Hash)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputFileListPaths1")))
            .willReturn(inputFileListPaths1)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/dependencyFile1")))
            .willReturn(dependencyFileHash)
        let targetScript = makeTargetScript()

        // When
        _ = try await subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then — path content hashes are sorted for determinism
        let expected = [
            dependencyFileHash,
            inputFileListPaths1,
            inputPaths1Hash,
            "outputPaths1",
            "outputFileListPaths1",
            "1",
            "tool1",
            "pre",
            "arg1",
            "arg2",
        ]
        verify(contentHasher)
            .hash(.value(expected))
            .called(1)
    }

    @Test
    func hash_targetAction_when_path_nil_callsMockHasherWithExpectedStrings() async throws {
        // Given
        let inputPaths1Hash = "inputPaths1-hash"
        let inputFileListPaths1 = "inputFileListPaths1-hash"
        let dependencyFileHash = "dependencyFile1-hash"
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths1")))
            .willReturn(inputPaths1Hash)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputFileListPaths1")))
            .willReturn(inputFileListPaths1)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/dependencyFile1")))
            .willReturn(dependencyFileHash)

        let targetScript = makeTargetScript()

        // When
        _ = try await subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then — path content hashes are sorted for determinism
        let expected = [
            dependencyFileHash,
            inputFileListPaths1,
            inputPaths1Hash,
            "outputPaths1",
            "outputFileListPaths1",
            "1",
            "tool1",
            "pre",
            "arg1",
            "arg2",
        ]
        verify(contentHasher)
            .hash(.value(expected))
            .called(1)
    }

    @Test
    func hash_targetAction_valuesAreNotHardcoded() async throws {
        // Given
        let inputPaths2Hash = "inputPaths2-hash"
        let inputFileListPaths2 = "inputFileListPaths2-hash"
        let dependencyFileHash = "/dependencyFilePath4-hash"
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths2")))
            .willReturn(inputPaths2Hash)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputFileListPaths2")))
            .willReturn(inputFileListPaths2)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/dependencyFilePath4")))
            .willReturn(dependencyFileHash)

        let targetScript = makeTargetScript(
            name: "2",
            order: .post,
            tool: "tool2",
            inputPaths: ["/inputPaths2"],
            inputFileListPaths: ["/inputFileListPaths2"],
            outputPaths: ["/outputPaths2"],
            outputFileListPaths: ["/outputFileListPaths2"],
            dependencyFile: try AbsolutePath(validating: "/dependencyFilePath4")
        )

        // When
        _ = try await subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then — path content hashes are sorted for determinism
        let expected = [
            dependencyFileHash,
            inputFileListPaths2,
            inputPaths2Hash,
            "outputPaths2",
            "outputFileListPaths2",
            "2",
            "tool2",
            "post",
            "arg1",
            "arg2",
        ]
        verify(contentHasher)
            .hash(.value(expected))
            .called(1)
    }

    @Test
    func hash_isIndependentFromInputFilesOrder() async throws {
        // Given
        let inputPaths1Hash = "inputPaths1-hash"
        let inputPaths2Hash = "inputPaths2-hash"
        let dependencyFileHash = "/dependencyFilePath4-hash"
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths1")))
            .willReturn(inputPaths1Hash)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths2")))
            .willReturn(inputPaths2Hash)
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/dependencyFilePath4")))
            .willReturn(dependencyFileHash)

        let targetScriptOrder1 = makeTargetScript(
            name: "2",
            order: .post,
            tool: "tool2",
            inputPaths: ["/inputPaths1", "/inputPaths2"],
            inputFileListPaths: [],
            outputPaths: [],
            outputFileListPaths: [],
            dependencyFile: try AbsolutePath(validating: "/dependencyFilePath4")
        )

        let targetScriptOrder2 = makeTargetScript(
            name: "2",
            order: .post,
            tool: "tool2",
            inputPaths: ["/inputPaths2", "/inputPaths1"],
            inputFileListPaths: [],
            outputPaths: [],
            outputFileListPaths: [],
            dependencyFile: try AbsolutePath(validating: "/dependencyFilePath4")
        )

        // When
        _ = try await subject.hash(targetScripts: [targetScriptOrder1], sourceRootPath: "/")
        _ = try await subject.hash(targetScripts: [targetScriptOrder2], sourceRootPath: "/")

        // Then — path content hashes are sorted for determinism
        let expected = [
            dependencyFileHash,
            inputPaths1Hash,
            inputPaths2Hash,
            "2",
            "tool2",
            "post",
            "arg1",
            "arg2",
        ]
        verify(contentHasher)
            .hash(.value(expected))
            .called(2)
    }

    @Test func hash_targetAction_embeddedScriptTextIsHashed() async throws {
        // Given
        let inputPaths1Hash = "inputPaths1-hash"
        given(contentHasher)
            .hash(path: .value(try AbsolutePath(validating: "/inputPaths1")))
            .willReturn(inputPaths1Hash)

        let targetScript = TargetScript(
            name: "EmbeddedScript",
            order: .pre,
            script: .embedded("echo hello"),
            inputPaths: ["/inputPaths1"],
            inputFileListPaths: [],
            outputPaths: [],
            outputFileListPaths: [],
            dependencyFile: nil
        )

        // When
        _ = try await subject.hash(targetScripts: [targetScript], sourceRootPath: "/")

        // Then
        let expected = [
            inputPaths1Hash,
            "echo hello",
            "EmbeddedScript",
            "",
            "pre",
        ]
        verify(contentHasher)
            .hash(.value(expected))
            .called(1)
    }

    @Test func hash_targetAction_differentEmbeddedScriptProducesDifferentHash() async throws {
        // Given
        let targetScript1 = TargetScript(
            name: "Script",
            order: .pre,
            script: .embedded("echo hello"),
            inputPaths: [],
            inputFileListPaths: [],
            outputPaths: [],
            outputFileListPaths: [],
            dependencyFile: nil
        )
        let targetScript2 = TargetScript(
            name: "Script",
            order: .pre,
            script: .embedded("echo world"),
            inputPaths: [],
            inputFileListPaths: [],
            outputPaths: [],
            outputFileListPaths: [],
            dependencyFile: nil
        )

        // When
        let hash1 = try await subject.hash(targetScripts: [targetScript1], sourceRootPath: "/")
        let hash2 = try await subject.hash(targetScripts: [targetScript2], sourceRootPath: "/")

        // Then
        #expect(hash1 != hash2)
    }

    @Test
    func hash_targetAction_withRelativePathsAndSRCROOTReplacement() async throws {
        // Given
        let sourceRootPath = try AbsolutePath(validating: "/project/root")
        let relativeInputHash = "relativeInput-hash"
        let absoluteInputHash = "absoluteInput-hash"

        given(contentHasher)
            .hash(path: .value(sourceRootPath.appending(try RelativePath(validating: "relative/input.txt"))))
            .willReturn(relativeInputHash)
        given(contentHasher)
            .hash(path: .value(sourceRootPath.appending(try RelativePath(validating: "srcroot/replaced.txt"))))
            .willReturn(absoluteInputHash)

        given(contentHasher)
            .hash(path: .value(sourceRootPath.appending(try RelativePath(validating: "relative/not-existing.txt"))))
            .willThrow(FileHandlerError.fileNotFound(try AbsolutePath(validating: "/")))

        let targetScript = TargetScript(
            name: "TestScript",
            order: .pre,
            script: .tool(path: "tool", args: ["arg"]),
            inputPaths: ["relative/input.txt", "relative/not-existing.txt"],
            inputFileListPaths: ["$(SRCROOT)/srcroot/replaced.txt"],
            outputPaths: ["relative/output.txt"],
            outputFileListPaths: ["$(SRCROOT)/srcroot/output.txt"],
            dependencyFile: nil
        )

        // When
        _ = try await subject.hash(targetScripts: [targetScript], sourceRootPath: sourceRootPath)

        // Then — path content hashes are sorted for determinism
        let expected = [
            absoluteInputHash,
            "relative/not-existing.txt",
            relativeInputHash,
            "relative/output.txt",
            "srcroot/output.txt",
            "TestScript",
            "tool",
            "pre",
            "arg",
        ]

        verify(contentHasher)
            .hash(.value(expected))
            .called(1)
    }
}
