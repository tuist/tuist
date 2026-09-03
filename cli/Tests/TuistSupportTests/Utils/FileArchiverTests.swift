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

        let archivePath = try await FileArchiver(paths: [directory]).zip(name: "App")

        let archiveSize = try #require(try await fileSystem.fileMetadata(at: archivePath)?.size)
        #expect(archiveSize < contentSize / 2)
    }

    @Test(.inTemporaryDirectory) func zip_round_trips_files_directories_symlinks_and_permissions() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = try await makeBundle(in: temporaryDirectory)

        let archivePath = try await FileArchiver(paths: [directory]).zip(name: "App")
        let unarchived = try await FileUnarchiver(path: archivePath).unzip()

        try await expectBundleRestored(at: unarchived.appending(component: "App.app"))
    }

    @Test(.inTemporaryDirectory) func zip_produces_an_archive_an_independent_implementation_can_read() async throws {
        let unzip = "/usr/bin/unzip"
        try #require(FileManager.default.isExecutableFile(atPath: unzip))
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = try await makeBundle(in: temporaryDirectory)

        let archivePath = try await FileArchiver(paths: [directory]).zip(name: "App")

        #expect(try run(unzip, ["-t", archivePath.pathString]).contains("No errors detected"))
        let extracted = temporaryDirectory.appending(component: "extracted")
        _ = try run(unzip, ["-q", archivePath.pathString, "-d", extracted.pathString])
        try await expectBundleRestored(at: extracted.appending(component: "App.app"))
    }

    @Test(.inTemporaryDirectory) func zip_archives_an_empty_directory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "Empty.app")
        try await fileSystem.makeDirectory(at: directory)

        let archivePath = try await FileArchiver(paths: [directory]).zip(name: "Empty")
        let unarchived = try await FileUnarchiver(path: archivePath).unzip()

        #expect(try await fileSystem.exists(unarchived.appending(component: "Empty.app"), isDirectory: true))
    }

    // MARK: - Helpers

    private func makeBundle(in temporaryDirectory: AbsolutePath) async throws -> AbsolutePath {
        let directory = temporaryDirectory.appending(component: "App.app")
        try await fileSystem.makeDirectory(at: directory.appending(component: "Frameworks"))
        try await fileSystem.writeText(
            String(repeating: "executable payload ", count: 50000),
            at: directory.appending(component: "App")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: directory.appending(component: "App").pathString
        )
        try await fileSystem.writeText("{}", at: directory.appending(components: "Frameworks", "Info.plist"))
        try await fileSystem.touch(directory.appending(component: "Empty"))
        try await fileSystem.writeText("ünïcödé", at: directory.appending(component: "Ünïcödé.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: directory.appending(component: "Current").pathString,
            withDestinationPath: "Frameworks"
        )
        return directory
    }

    private func expectBundleRestored(at bundle: AbsolutePath) async throws {
        #expect(
            try await fileSystem.readTextFile(at: bundle.appending(component: "App"))
                == String(repeating: "executable payload ", count: 50000)
        )
        #expect(try await fileSystem.readTextFile(at: bundle.appending(components: "Frameworks", "Info.plist")) == "{}")
        #expect(try await fileSystem.readTextFile(at: bundle.appending(component: "Ünïcödé.txt")) == "ünïcödé")
        #expect(try await fileSystem.exists(bundle.appending(component: "Empty")))
        #expect(try await fileSystem.exists(bundle.appending(component: "Frameworks"), isDirectory: true))

        let permissions = try FileManager.default
            .attributesOfItem(atPath: bundle.appending(component: "App").pathString)[.posixPermissions] as? NSNumber
        #expect(permissions?.uint16Value == 0o755)

        let linkPath = bundle.appending(component: "Current").pathString
        let linkType = try FileManager.default.attributesOfItem(atPath: linkPath)[.type] as? FileAttributeType
        #expect(linkType == .typeSymbolicLink)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: linkPath) == "Frameworks")
    }

    private func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
