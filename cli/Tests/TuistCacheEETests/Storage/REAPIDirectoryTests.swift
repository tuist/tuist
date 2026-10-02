import FileSystem
import FileSystemTesting
import Foundation
import Path
import SwiftProtobuf
import Testing
import TuistREAPI

struct REAPIDirectoryTests {
    @Test(.inTemporaryDirectory) func preservesVersionedFrameworkSymlinksAndExecutableBits() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let source = directory.appending(component: "source").url
        let version = source.appendingPathComponent("Shared.framework/Versions/A")
        let manager = FileManager.default
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: AbsolutePath(validating: version.path))
        try await fileSystem.makeDirectory(at: AbsolutePath(validating: version.path).appending(components: [
            "Resources",
            "Empty",
        ]))
        let binary = version.appendingPathComponent("Shared")
        try await fileSystem.writeText("executable", at: AbsolutePath(validating: binary.path))
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try manager.createSymbolicLink(
            atPath: source.appendingPathComponent("Shared.framework/Versions/Current").path,
            withDestinationPath: "A"
        )
        try manager.createSymbolicLink(
            atPath: source.appendingPathComponent("Shared.framework/Shared").path,
            withDestinationPath: "Versions/Current/Shared"
        )
        let rawLink = "Versions/Current/../A/Shared"
        try manager.createSymbolicLink(
            atPath: source.appendingPathComponent("Shared.framework/Alias").path,
            withDestinationPath: rawLink
        )
        let scratch = directory.appending(component: "scratch").url
        try await fileSystem.makeDirectory(at: AbsolutePath(validating: scratch.path))
        let snapshot = try await REAPIDirectory.snapshot(at: source, scratch: scratch)
        let treePath = try #require(snapshot.blobs[snapshot.tree])
        let tree = try REAPI.Tree(serializedBytes: await fileSystem.readFile(at: AbsolutePath(validating: treePath.path)))
        #expect(!tree.children.isEmpty)
        #expect(Set(snapshot.blobs.keys) == [snapshot.tree, REAPI.digest(Data("executable".utf8))])
        #expect(try await fileSystem.contentsOfDirectory(AbsolutePath(validating: scratch.path))
            .map(\.basename) == [snapshot.tree.hash])
        let output = directory.appending(component: "output").url
        try await REAPIDirectory.materialize(tree, at: output) { try #require(snapshot.blobs[$0]) }
        #expect(try await fileSystem.readFile(at: AbsolutePath(validating: output.path).appending(components: [
            "Shared.framework",
            "Shared",
        ])) == Data("executable".utf8))
        #expect(try manager
            .destinationOfSymbolicLink(atPath: output.appendingPathComponent("Shared.framework/Versions/Current").path) == "A")
        #expect(manager.isExecutableFile(atPath: output.appendingPathComponent("Shared.framework/Shared").path))
        #expect(try await fileSystem.exists(AbsolutePath(validating: output.path).appending(components: [
            "Shared.framework",
            "Versions",
            "A",
            "Resources",
            "Empty",
        ])))
        #expect(try manager
            .destinationOfSymbolicLink(atPath: output.appendingPathComponent("Shared.framework/Alias").path) == rawLink)
        let second = try await REAPIDirectory.snapshot(at: output, scratch: scratch)
        #expect(second.tree == snapshot.tree)
    }

    @Test(.inTemporaryDirectory) func rejectsEscapeThroughChainedSymlinks() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let child = REAPI.Directory.with {
            $0.symlinks = [.with { $0.name = "short"; $0.target = "../other" }]
        }
        let empty = REAPI.Directory()
        let childDigest = REAPI.digest(try child.serializedData())
        let emptyDigest = REAPI.digest(try empty.serializedData())
        let tree = REAPI.Tree.with {
            $0.root.directories = [
                .with { $0.name = "nested"; $0.digest = childDigest },
                .with { $0.name = "other"; $0.digest = emptyDigest },
            ]
            $0.root.symlinks = [.with { $0.name = "escape"; $0.target = "nested/short/../../outside" }]
            $0.children = [child, empty]
        }
        await #expect(throws: REAPICacheError.self) {
            try await REAPIDirectory.materialize(tree, at: directory.appending(component: "output").url) { _ in
                throw REAPICacheError.invalidTree
            }
        }
    }

    @Test(.inTemporaryDirectory) func rejectsEscapingNamesAndSymlinks() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        for name in ["../escape", "/absolute", ".", ".."] {
            let tree = REAPI.Tree.with { $0.root.directories = [.with { $0.name = name }] }
            await #expect(throws: REAPICacheError.self) {
                try await REAPIDirectory
                    .materialize(tree, at: directory.appending(component: UUID().uuidString).url) { _ in
                        throw REAPICacheError.invalidTree
                    }
            }
        }
        for target in ["../../escape", "/etc/passwd"] {
            let tree = REAPI.Tree.with { $0.root.symlinks = [.with { $0.name = "link"; $0.target = target }] }
            await #expect(throws: REAPICacheError.self) {
                try await REAPIDirectory
                    .materialize(tree, at: directory.appending(component: UUID().uuidString).url) { _ in
                        throw REAPICacheError.invalidTree
                    }
            }
        }
    }
}
