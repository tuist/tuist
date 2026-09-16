import FileSystem
import FileSystemTesting
import Foundation
import SwiftProtobuf
import Testing
import TuistREAPI

struct REAPIDirectoryTests {
    @Test(.inTemporaryDirectory) func preservesVersionedFrameworkSymlinksAndExecutableBits() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let source = directory.appending(component: "source").url
        let version = source.appendingPathComponent("Shared.framework/Versions/A")
        let manager = FileManager.default
        try manager.createDirectory(at: version, withIntermediateDirectories: true)
        let binary = version.appendingPathComponent("Shared")
        try Data("executable".utf8).write(to: binary)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try manager.createSymbolicLink(
            atPath: source.appendingPathComponent("Shared.framework/Versions/Current").path,
            withDestinationPath: "A"
        )
        try manager.createSymbolicLink(
            atPath: source.appendingPathComponent("Shared.framework/Shared").path,
            withDestinationPath: "Versions/Current/Shared"
        )
        let scratch = directory.appending(component: "scratch").url
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        let snapshot = try REAPIDirectory.snapshot(at: source, scratch: scratch)
        let tree = try REAPI.Tree(serializedBytes: Data(contentsOf: #require(snapshot.blobs[snapshot.tree])))
        let output = directory.appending(component: "output").url
        try REAPIDirectory.materialize(tree, at: output) { try #require(snapshot.blobs[$0]) }
        #expect(try Data(contentsOf: output.appendingPathComponent("Shared.framework/Shared")) == Data("executable".utf8))
        #expect(try manager
            .destinationOfSymbolicLink(atPath: output.appendingPathComponent("Shared.framework/Versions/Current").path) == "A")
        #expect(manager.isExecutableFile(atPath: output.appendingPathComponent("Shared.framework/Shared").path))
        let second = try REAPIDirectory.snapshot(at: output, scratch: scratch)
        #expect(second.tree == snapshot.tree)
    }

    @Test(.inTemporaryDirectory) func rejectsEscapeThroughChainedSymlinks() throws {
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
        #expect(throws: REAPICacheError.self) {
            try REAPIDirectory.materialize(tree, at: directory.appending(component: "output").url) { _ in
                throw REAPICacheError.invalidTree
            }
        }
    }

    @Test(.inTemporaryDirectory) func rejectsEscapingNamesAndSymlinks() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        for name in ["../escape", "/absolute", ".", ".."] {
            let tree = REAPI.Tree.with { $0.root.directories = [.with { $0.name = name }] }
            #expect(throws: REAPICacheError.self) {
                try REAPIDirectory
                    .materialize(tree, at: directory.appending(component: UUID().uuidString).url) { _ in
                        throw REAPICacheError.invalidTree
                    }
            }
        }
        for target in ["../../escape", "/etc/passwd"] {
            let tree = REAPI.Tree.with { $0.root.symlinks = [.with { $0.name = "link"; $0.target = target }] }
            #expect(throws: REAPICacheError.self) {
                try REAPIDirectory
                    .materialize(tree, at: directory.appending(component: UUID().uuidString).url) { _ in
                        throw REAPICacheError.invalidTree
                    }
            }
        }
    }
}
