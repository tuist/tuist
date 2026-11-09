import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistSupport

struct FileUnarchiverTests {
    @Test(.inTemporaryDirectory)
    func preserves_optional_resource_links_in_app_archives() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let app = directory.appending(component: "App.app")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: app)
        try await fileSystem.writeText("app resource", at: app.appending(component: "resource.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: app.appending(component: "optional").pathString, withDestinationPath: "missing.txt"
        )
        let archiver = try FileArchivingFactory().makeFileArchiver(for: [app])
        let archive = try await archiver.zip(name: "preview")
        let unarchiver = try FileUnarchiver(path: archive)

        let unpacked = try await unarchiver.unzip()

        #expect(try await fileSystem
            .readTextFile(at: unpacked.appending(components: "App.app", "resource.txt")) == "app resource")
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: unpacked.appending(components: "App.app", "optional").pathString
        ) == "missing.txt")
        try await unarchiver.delete()
        try await archiver.delete()
    }

    @Test(.inTemporaryDirectory, arguments: ["absolute", "relative", "symlink-parent"])
    func rejects_symlinks_outside_the_archive(kind: String) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let source = directory.appending(component: "distribution")
        let outside = directory.appending(component: "outside.txt")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: source)
        try await fileSystem.writeText("untouched", at: outside)
        let target: String
        switch kind {
        case "absolute": target = outside.pathString
        case "symlink-parent":
            try await fileSystem.makeDirectory(at: source.appending(component: "dir"))
            try FileManager.default.createSymbolicLink(
                atPath: source.appending(components: "dir", "up").pathString, withDestinationPath: "../.."
            )
            target = "dir/up/../outside.txt"
        default: target = "../../outside.txt"
        }
        try FileManager.default.createSymbolicLink(
            atPath: source.appending(component: "escape").pathString,
            withDestinationPath: target
        )
        let archiver = try FileArchivingFactory().makeFileArchiver(for: [source])
        let archive = try await archiver.zip(name: "preview")
        let unarchiver = try FileUnarchiver(path: archive)
        await #expect(throws: (any Error).self) { try await unarchiver.unzipSelfContained() }
        #expect(try await fileSystem.readTextFile(at: outside) == "untouched")
        try await unarchiver.delete()
        try await archiver.delete()
    }
}
