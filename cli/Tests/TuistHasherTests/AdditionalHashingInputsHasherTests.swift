import FileSystem
import FileSystemTesting
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
            inputs: [
                .path(filePath, isDeclaredAbsolute: false),
                .path(folderPath, isDeclaredAbsolute: false),
            ],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(
            result.hash ==
                "path-Codegen-content-folder-content-hash|path-template.stencil-content-file-content-hash-combined-hash"
        )
        #expect(result.hashedPaths == [
            filePath: "file-content",
            folderPath: "folder-content",
        ])
    }

    @Test
    func hash_distinguishesPathsWithIdenticalContent() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")
        let firstPath = sourceRootPath.appending(component: "first.txt")
        let secondPath = sourceRootPath.appending(component: "second.txt")
        given(contentHasher)
            .hash(path: .any)
            .willReturn("same-content")

        let firstResult = try await subject.hash(
            inputs: [.path(firstPath, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )
        let secondResult = try await subject.hash(
            inputs: [.path(secondPath, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: sourceRootPath
        )

        #expect(
            firstResult.hash ==
                "path-first.txt-content-same-content-hash-combined-hash"
        )
        #expect(
            secondResult.hash ==
                "path-second.txt-content-same-content-hash-combined-hash"
        )
    }

    @Test
    func hash_reusesAnExistingPathHash() async throws {
        let sourceRootPath = try AbsolutePath(validating: "/project")
        let filePath = sourceRootPath.appending(component: "template.stencil")

        let result = try await subject.hash(
            inputs: [.path(filePath, isDeclaredAbsolute: false)],
            hashedPaths: [filePath: "cached-content"],
            sourceRootPath: sourceRootPath
        )

        #expect(result.hash == "path-template.stencil-content-cached-content-hash-combined-hash")
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

    @Test
    func hash_usesStableIdentifiersForDeclaredAbsoluteAndRelativeExternalPaths() async throws {
        let absolutePath = try AbsolutePath(validating: "/opt/codegen/schema.json")
        let firstRelativePath = try AbsolutePath(validating: "/checkout/shared/schema.json")
        let secondRelativePath = try AbsolutePath(validating: "/deep/checkout/shared/schema.json")
        given(contentHasher)
            .hash(path: .any)
            .willReturn("same-content")

        let firstAbsolute = try await subject.hash(
            inputs: [.path(absolutePath, isDeclaredAbsolute: true)],
            hashedPaths: [:],
            sourceRootPath: try AbsolutePath(validating: "/checkout/project")
        )
        let secondAbsolute = try await subject.hash(
            inputs: [.path(absolutePath, isDeclaredAbsolute: true)],
            hashedPaths: [:],
            sourceRootPath: try AbsolutePath(validating: "/deep/checkout/project")
        )
        let firstRelative = try await subject.hash(
            inputs: [.path(firstRelativePath, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: try AbsolutePath(validating: "/checkout/project")
        )
        let secondRelative = try await subject.hash(
            inputs: [.path(secondRelativePath, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: try AbsolutePath(validating: "/deep/checkout/project")
        )

        #expect(firstAbsolute.hash == secondAbsolute.hash)
        #expect(firstRelative.hash == secondRelative.hash)
    }

    @Test(.inTemporaryDirectory)
    func hash_changesWhenAFileInADirectoryIsRenamed() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "Codegen")
        let originalPath = directory.appending(component: "Model.stencil")
        let renamedPath = directory.appending(component: "Entity.stencil")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: directory)
        try await fileSystem.writeText("template", at: originalPath)
        let subject = AdditionalHashingInputsHasher(contentHasher: ContentHasher())

        let before = try await subject.hash(
            inputs: [.path(directory, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: temporaryDirectory
        )
        try await fileSystem.remove(originalPath)
        try await fileSystem.writeText("template", at: renamedPath)
        let after = try await subject.hash(
            inputs: [.path(directory, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: temporaryDirectory
        )

        #expect(before.hash != after.hash)
    }

    @Test(.inTemporaryDirectory)
    func hash_changesWhenFileContentsAreSwappedWithinADirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "Codegen")
        let firstPath = directory.appending(component: "Model.stencil")
        let secondPath = directory.appending(component: "View.stencil")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: directory)
        try await fileSystem.writeText("model", at: firstPath)
        try await fileSystem.writeText("view", at: secondPath)
        let subject = AdditionalHashingInputsHasher(contentHasher: ContentHasher())

        let before = try await subject.hash(
            inputs: [.path(directory, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: temporaryDirectory
        )
        try await fileSystem.writeText("view", at: firstPath)
        try await fileSystem.writeText("model", at: secondPath)
        let after = try await subject.hash(
            inputs: [.path(directory, isDeclaredAbsolute: false)],
            hashedPaths: [:],
            sourceRootPath: temporaryDirectory
        )

        #expect(before.hash != after.hash)
    }
}
