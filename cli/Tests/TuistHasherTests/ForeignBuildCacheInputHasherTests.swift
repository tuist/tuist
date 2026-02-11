import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistHasher

struct ForeignBuildCacheInputHasherTests {
    private var subject: ForeignBuildCacheInputHasher!
    private var contentHasher: MockContentHashing!
    private var system: MockSystem!

    init() {
        contentHasher = .init()
        system = MockSystem()

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }

        subject = ForeignBuildCacheInputHasher(
            contentHasher: contentHasher,
            system: system
        )
    }

    @Test
    func hash_fileInput_hashesFileAndReturnsCombinedHash() async throws {
        // Given
        let filePath = try AbsolutePath(validating: "/project/build.gradle.kts")
        given(contentHasher)
            .hash(path: .value(filePath))
            .willReturn("file-content-hash")

        // When
        let result = try await subject.hash(
            cacheInputs: [.file(filePath)],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hash == "file-content-hash-hash")
        #expect(result.hashedPaths[filePath] == "file-content-hash")
    }

    @Test
    func hash_fileInput_reusesCachedHash() async throws {
        // Given
        let filePath = try AbsolutePath(validating: "/project/build.gradle.kts")
        let existingHashedPaths: [AbsolutePath: String] = [filePath: "cached-hash"]

        // When
        let result = try await subject.hash(
            cacheInputs: [.file(filePath)],
            hashedPaths: existingHashedPaths
        )

        // Then
        #expect(result.hash == "cached-hash-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(0)
    }

    @Test
    func hash_folderInput_hashesFolderAndReturnsCombinedHash() async throws {
        // Given
        let folderPath = try AbsolutePath(validating: "/project/src")
        given(contentHasher)
            .hash(path: .value(folderPath))
            .willReturn("folder-content-hash")

        // When
        let result = try await subject.hash(
            cacheInputs: [.folder(folderPath)],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hash == "folder-content-hash-hash")
        #expect(result.hashedPaths[folderPath] == "folder-content-hash")
    }

    @Test
    func hash_scriptInput_runsScriptAndHashesOutput() async throws {
        // Given
        let script = "git rev-parse HEAD"
        system.succeedCommand(["/bin/sh", "-c", script], output: "abc123")

        // When
        let result = try await subject.hash(
            cacheInputs: [.script(script)],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hash == "abc123-hash-hash")
    }

    @Test
    func hash_multipleInputs_combinesAllHashes() async throws {
        // Given
        let filePath = try AbsolutePath(validating: "/project/build.gradle.kts")
        let folderPath = try AbsolutePath(validating: "/project/src")
        given(contentHasher)
            .hash(path: .value(filePath))
            .willReturn("file-hash")
        given(contentHasher)
            .hash(path: .value(folderPath))
            .willReturn("folder-hash")

        // When
        let result = try await subject.hash(
            cacheInputs: [.file(filePath), .folder(folderPath)],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hash == "file-hashfolder-hash-hash")
        #expect(result.hashedPaths[filePath] == "file-hash")
        #expect(result.hashedPaths[folderPath] == "folder-hash")
    }

    @Test
    func hash_emptyInputs_returnsHashOfEmptyString() async throws {
        // When
        let result = try await subject.hash(
            cacheInputs: [],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hash == "-hash")
    }

    @Test(.inTemporaryDirectory)
    func hash_globInput_hashesMatchedFiles() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let subjectWithRealFS = ForeignBuildCacheInputHasher(
            contentHasher: contentHasher,
            fileSystem: fileSystem,
            system: system
        )

        let srcDir = temporaryDirectory.appending(component: "src")
        try await fileSystem.makeDirectory(at: srcDir)
        let file1 = srcDir.appending(component: "File1.kt")
        let file2 = srcDir.appending(component: "File2.kt")
        try await fileSystem.writeText("content1", at: file1)
        try await fileSystem.writeText("content2", at: file2)

        given(contentHasher)
            .hash(path: .value(file1))
            .willReturn("file1-hash")
        given(contentHasher)
            .hash(path: .value(file2))
            .willReturn("file2-hash")

        let globPattern = srcDir.pathString + "/*.kt"

        // When
        let result = try await subjectWithRealFS.hash(
            cacheInputs: [.glob(globPattern)],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hashedPaths[file1] == "file1-hash")
        #expect(result.hashedPaths[file2] == "file2-hash")
    }
}
