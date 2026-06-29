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

    @Test(.inTemporaryDirectory) func execute_createsSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let destination = temporaryDirectory.appending(components: "Artifacts", "Module.xcframework")
        let link = temporaryDirectory.appending(components: "Derived", "FrameworkSearchPaths", "Module.xcframework")
        try await fileSystem.makeDirectory(at: destination)

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: destination)),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(link) == destination)
    }

    @Test(.inTemporaryDirectory) func execute_replacesDanglingSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let oldDestination = temporaryDirectory.appending(components: "Artifacts", "old", "Module.xcframework")
        let newDestination = temporaryDirectory.appending(components: "Artifacts", "new", "Module.xcframework")
        let link = temporaryDirectory.appending(components: "Derived", "FrameworkSearchPaths", "Module.xcframework")
        try await fileSystem.makeDirectory(at: oldDestination)
        try await fileSystem.makeDirectory(at: newDestination)
        try await fileSystem.makeDirectory(at: link.parentDirectory)
        try await fileSystem.createSymbolicLink(from: link, to: oldDestination)
        try await fileSystem.remove(oldDestination)

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: newDestination)),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(link) == newDestination)
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

    @Test(.inTemporaryDirectory) func execute_cleansStaleGeneratedSymbolicLinks() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "FrameworkSearchPaths")
        let activeDestination = temporaryDirectory.appending(components: "Artifacts", "Active.framework")
        let staleDestination = temporaryDirectory.appending(components: "Artifacts", "Stale.framework")
        let activeLink = directory.appending(components: "Swift", "App", "Active.framework")
        let staleLink = directory.appending(components: "Swift", "Deleted", "Stale.framework")
        try await fileSystem.makeDirectory(at: activeDestination)
        try await fileSystem.makeDirectory(at: staleDestination)
        try await fileSystem.makeDirectory(at: activeLink.parentDirectory)
        try await fileSystem.makeDirectory(at: staleLink.parentDirectory)
        try await fileSystem.createSymbolicLink(from: activeLink, to: activeDestination)
        try await fileSystem.createSymbolicLink(from: staleLink, to: staleDestination)
        try await fileSystem.remove(staleDestination)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: [directory],
                    activeFilesByDirectory: [directory: [activeLink]],
                    include: ["**/*.framework"]
                )
            ),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(activeLink) == activeDestination)
        await #expect(throws: FileSystemError.absentSymbolicLink(staleLink)) {
            try await fileSystem.resolveSymbolicLink(staleLink)
        }
        #expect(try await !fileSystem.contentsOfDirectory(staleLink.parentDirectory).contains(staleLink))
    }

    private func modificationDate(at path: AbsolutePath) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return try #require(attributes[.modificationDate] as? Date)
    }
}
