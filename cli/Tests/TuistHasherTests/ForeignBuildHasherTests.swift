import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistHasher

struct ForeignBuildHasherTests {
    private let subject: ForeignBuildHasher
    private let contentHasher = MockContentHashing()
    private let system = MockSystem()

    init() {
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }

        subject = ForeignBuildHasher(
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
            inputs: [.file(filePath)],
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
            inputs: [.file(filePath)],
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
            inputs: [.folder(folderPath)],
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
            inputs: [.script(script)],
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
            inputs: [.file(filePath), .folder(folderPath)],
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
            inputs: [],
            hashedPaths: [:]
        )

        // Then
        #expect(result.hash == "-hash")
    }

}
