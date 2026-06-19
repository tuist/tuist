import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

struct SideEffectDescriptorExecutorTests {
    private let fileSystem = FileSystem()
    private let commandRunner = MockCommandRunner()
    private let subject: SideEffectDescriptorExecutor

    init() {
        subject = SideEffectDescriptorExecutor(fileSystem: fileSystem, commandRunner: commandRunner)
    }

    @Test(.inTemporaryDirectory) func execute_doesNotRewriteFileWhenContentsAreUnchanged() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "Generated.swift")
        let contents = Data("let value = 1\n".utf8)
        let oldDate = Date(timeIntervalSince1970: 1)
        try await fileSystem.writeText("let value = 1\n", at: path)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: path.pathString
        )

        try await subject.execute(sideEffects: [
            .file(FileDescriptor(path: path, contents: contents)),
        ])

        #expect(try modificationDate(at: path) == oldDate)
    }

    @Test(.inTemporaryDirectory) func execute_rewritesFileWhenContentsChange() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "Generated.swift")
        let oldDate = Date(timeIntervalSince1970: 1)
        try await fileSystem.writeText("let value = 1\n", at: path)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: path.pathString
        )

        try await subject.execute(sideEffects: [
            .file(FileDescriptor(path: path, contents: Data("let value = 2\n".utf8))),
        ])

        #expect(try await fileSystem.readTextFile(at: path) == "let value = 2\n")
        #expect(try modificationDate(at: path) > oldDate)
    }

    @Test(.inTemporaryDirectory) func execute_cleansStaleGeneratedFiles() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory).appending(component: "ModuleMaps")
        let activeFile = directory.appending(component: "App-deps.modulemap")
        let staleFile = directory.appending(component: "Deleted-deps.modulemap")
        let preservedFile = directory.appending(component: "Package.modulemap")
        try await fileSystem.makeDirectory(at: directory)
        try await fileSystem.writeText("active", at: activeFile)
        try await fileSystem.writeText("stale", at: staleFile)
        try await fileSystem.writeText("preserved", at: preservedFile)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: [directory],
                    activeFilesByDirectory: [directory: [activeFile]],
                    include: ["*-deps.modulemap"]
                )
            ),
        ])

        #expect(try await fileSystem.exists(activeFile))
        #expect(try await !fileSystem.exists(staleFile))
        #expect(try await fileSystem.exists(preservedFile))
    }

    private func modificationDate(at path: AbsolutePath) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return try #require(attributes[.modificationDate] as? Date)
    }
}
