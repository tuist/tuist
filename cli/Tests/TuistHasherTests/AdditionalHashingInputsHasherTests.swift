import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistHasher

struct AdditionalHashingInputsHasherTests {
    private let contentHasher = MockContentHashing()
    private let commandRunner = MockCommandRunner()
    private let subject: AdditionalHashingInputsHasher

    init() {
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { "\($0)-hash" }
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { "\($0.joined(separator: "|"))-combined-hash" }

        subject = AdditionalHashingInputsHasher(
            contentHasher: contentHasher,
            commandRunner: commandRunner
        )
    }

    @Test
    func hash_returnsNilForEmptyInputs() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")

        let result = try await subject.hash(
            inputs: [],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(result.hash == nil)
        #expect(result.hashedPaths.isEmpty)
    }

    @Test
    func hash_hashesFilesAndDirectoriesAndReturnsTheirHashes() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")
        let filePath = sourceRootPath.appending(component: "template.stencil")
        let folderPath = sourceRootPath.appending(component: "Codegen")
        given(contentHasher)
            .hash(path: .value(filePath))
            .willReturn("file-content")
        given(contentHasher)
            .hash(path: .value(folderPath))
            .willReturn("folder-content")

        let result = try await subject.hash(
            inputs: [.path(filePath), .path(folderPath)],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(
            result.hash ==
                "path-file-content-hash|path-folder-content-hash-combined-hash"
        )
        #expect(result.hashedPaths == [
            filePath: "file-content",
            folderPath: "folder-content",
        ])
    }

    @Test
    func hash_reusesAnExistingPathHash() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")
        let filePath = sourceRootPath.appending(component: "template.stencil")

        let result = try await subject.hash(
            inputs: [.path(filePath)],
            hashedPaths: [filePath: "cached-content"],
            sourceRootPath: sourceRootPath
        )

        #expect(result.hash == "path-cached-content-hash-combined-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(0)
    }

    @Test
    func hash_includesStringsAndScriptOutput() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")
        let script = "codegen --version"
        commandRunner.succeedCommand(["/bin/sh", "-c", script], output: "1.2.3")

        let result = try await subject.hash(
            inputs: [.string("production"), .script(script)],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(
            result.hash ==
                "script-1.2.3-hash|string-production-hash-combined-hash"
        )
        #expect(commandRunner.workingDirectories == [sourceRootPath])
    }

    @Test
    func hash_includesEnvironmentVariableNamesValuesAndMissingState() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")
        let subject = AdditionalHashingInputsHasher(
            contentHasher: contentHasher,
            commandRunner: commandRunner,
            environmentVariables: {
                [
                    "CONFIGURATION": "release",
                    "EMPTY": "",
                ]
            }
        )

        let result = try await subject.hash(
            inputs: [
                .environmentVariable("CONFIGURATION"),
                .environmentVariable("EMPTY"),
                .environmentVariable("MISSING"),
            ],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(
            result.hash ==
                "environment-variable-CONFIGURATION-value-release-hash|environment-variable-EMPTY-value--hash|environment-variable-MISSING-missing-hash-combined-hash"
        )
    }

    @Test
    func hash_isStableWhenInputsAreReordered() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")

        let ordered = try await subject.hash(
            inputs: [.string("a"), .string("b")],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )
        let reordered = try await subject.hash(
            inputs: [.string("b"), .string("a")],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(ordered.hash == reordered.hash)
    }
}
