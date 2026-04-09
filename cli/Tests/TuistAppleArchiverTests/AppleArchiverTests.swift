import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAppleArchiver

struct AppleArchiverTests {
    let subject = AppleArchiver()

    @Test(.inTemporaryDirectory) func compress_and_decompress_roundtrip() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("hello world", at: sourceDir.appending(component: "file.txt"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let exists = try await fileSystem.exists(archivePath)
        #expect(exists)

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let content = try await fileSystem.readTextFile(at: extractDir.appending(component: "file.txt"))
        #expect(content == "hello world")
    }

    @Test(.inTemporaryDirectory) func compress_and_decompress_preserves_symlinks() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("target content", at: sourceDir.appending(component: "target.txt"))
        try await fileSystem.createSymbolicLink(
            from: sourceDir.appending(component: "link"),
            to: try RelativePath(validating: "target.txt")
        )

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let resolvedLink = try await fileSystem.resolveSymbolicLink(extractDir.appending(component: "link"))
        #expect(resolvedLink == extractDir.appending(component: "target.txt"))

        let content = try await fileSystem.readTextFile(at: extractDir.appending(component: "link"))
        #expect(content == "target content")
    }

    @Test(.inTemporaryDirectory) func compress_and_decompress_preserves_directory_structure() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        let nestedDir = sourceDir.appending(components: ["a", "b", "c"])
        try await fileSystem.makeDirectory(at: nestedDir)
        try await fileSystem.writeText("deep", at: nestedDir.appending(component: "deep.txt"))
        try await fileSystem.writeText("root", at: sourceDir.appending(component: "root.txt"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let rootContent = try await fileSystem.readTextFile(at: extractDir.appending(component: "root.txt"))
        #expect(rootContent == "root")

        let deepContent = try await fileSystem.readTextFile(
            at: extractDir.appending(components: ["a", "b", "c", "deep.txt"])
        )
        #expect(deepContent == "deep")
    }

    @Test(.inTemporaryDirectory) func compress_excludes_matching_patterns() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("keep", at: sourceDir.appending(component: "file.txt"))
        let dsymDir = sourceDir.appending(components: ["Module.framework.dSYM", "Contents", "Resources"])
        try await fileSystem.makeDirectory(at: dsymDir)
        try await fileSystem.writeText("debug", at: dsymDir.appending(component: "DWARF"))
        let swiftmoduleDir = sourceDir.appending(component: "Module.swiftmodule")
        try await fileSystem.makeDirectory(at: swiftmoduleDir)
        try await fileSystem.writeText("module", at: swiftmoduleDir.appending(component: "arm64.swiftmodule"))

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(
            directory: sourceDir,
            to: archivePath,
            excludePatterns: [".dSYM", ".swiftmodule"]
        )

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let fileExists = try await fileSystem.exists(extractDir.appending(component: "file.txt"))
        #expect(fileExists)
        let dsymExists = try await fileSystem.exists(extractDir.appending(component: "Module.framework.dSYM"))
        #expect(!dsymExists)
        let swiftmoduleExists = try await fileSystem.exists(extractDir.appending(component: "Module.swiftmodule"))
        #expect(!swiftmoduleExists)
    }

    @Test(.inTemporaryDirectory) func compress_handles_broken_symlinks() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceDir = temporaryDirectory.appending(component: "source")
        try await fileSystem.makeDirectory(at: sourceDir)
        try await fileSystem.writeText("keep", at: sourceDir.appending(component: "file.txt"))
        try await fileSystem.createSymbolicLink(
            from: sourceDir.appending(component: "broken_link"),
            to: try AbsolutePath(validating: "/nonexistent/target")
        )

        let archivePath = temporaryDirectory.appending(component: "archive.aar")
        try await subject.compress(directory: sourceDir, to: archivePath, excludePatterns: [])

        let extractDir = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractDir)
        try await subject.decompress(archive: archivePath, to: extractDir)

        let fileContent = try await fileSystem.readTextFile(at: extractDir.appending(component: "file.txt"))
        #expect(fileContent == "keep")
        let linkDest = try FileManager.default.destinationOfSymbolicLink(
            atPath: extractDir.appending(component: "broken_link").pathString
        )
        #expect(linkDest == "/nonexistent/target")
    }
}
