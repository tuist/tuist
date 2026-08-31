import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistSupport

struct FileArchiverTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func zip_compresses_the_archived_content() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "App.app")
        try await fileSystem.makeDirectory(at: directory)
        let content = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 100_000)
        try await fileSystem.writeText(content, at: directory.appending(component: "Binary"))
        let contentSize = try #require(try await fileSystem.fileMetadata(at: directory.appending(component: "Binary"))?.size)

        let subject = try FileArchiver(paths: [directory])
        let archivePath = try await subject.zip(name: "App")

        let archiveSize = try #require(try await fileSystem.fileMetadata(at: archivePath)?.size)
        #expect(archiveSize < contentSize / 2)
    }

    @Test(.inTemporaryDirectory) func zip_produces_an_archive_that_unarchives_to_the_original_content() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "App.app")
        try await fileSystem.makeDirectory(at: directory)
        let content = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1000)
        try await fileSystem.writeText(content, at: directory.appending(component: "Binary"))

        let subject = try FileArchiver(paths: [directory])
        let archivePath = try await subject.zip(name: "App")
        let unarchivedDirectory = try await FileUnarchiver(path: archivePath).unzip()

        let unarchivedContent = try await fileSystem.readTextFile(
            at: unarchivedDirectory.appending(components: "App.app", "Binary")
        )
        #expect(unarchivedContent == content)
    }
}
