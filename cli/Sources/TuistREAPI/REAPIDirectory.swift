import FileSystem
import Foundation
import Path
import SwiftProtobuf

public enum REAPIDirectory {
    public struct Snapshot {
        public let tree: REAPI.Digest
        public let blobs: [REAPI.Digest: URL]
    }

    public static func snapshot(
        at root: URL,
        scratch: URL,
        fileSystem: FileSysteming = FileSystem()
    ) async throws -> Snapshot {
        let manager = FileManager.default
        var blobs: [REAPI.Digest: URL] = [:]
        var children: [REAPI.Digest: REAPI.Directory] = [:]
        func persist(_ data: Data) throws -> REAPI.Digest {
            let digest = REAPI.digest(data)
            let path = scratch.appendingPathComponent(digest.hash)
            try data.write(to: path, options: .atomic)
            blobs[digest] = path
            return digest
        }
        func visit(_ path: URL, depth: Int) async throws -> REAPI.Directory {
            guard depth < 128 else { throw REAPICacheError.invalidTree }
            var directory = REAPI.Directory()
            for file in try await fileSystem.contentsOfDirectory(AbsolutePath(validating: path.path))
                .map(\.url)
                .sorted(by: { $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8) })
            {
                let attributes = try manager.attributesOfItem(atPath: file.path)
                switch attributes[.type] as? FileAttributeType {
                case .typeSymbolicLink:
                    let target = try manager.destinationOfSymbolicLink(atPath: file.path)
                    try validateLink(target, at: file, root: root)
                    try validateResolvedLink(file, root: root)
                    directory.symlinks.append(.with { $0.name = file.lastPathComponent; $0.target = target })
                case .typeDirectory:
                    let child = try await visit(file, depth: depth + 1)
                    let digest = REAPI.digest(try child.serializedData())
                    children[digest] = child
                    directory.directories.append(.with { $0.name = file.lastPathComponent; $0.digest = digest })
                case .typeRegular:
                    let digest = try REAPI.digest(file: file)
                    blobs[digest] = file
                    directory.files.append(.with {
                        $0.name = file.lastPathComponent
                        $0.digest = digest
                        $0.isExecutable = ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o111 != 0
                    })
                default: throw REAPICacheError.invalidTree
                }
            }
            return directory
        }
        let directory = try await visit(root, depth: 0)
        let tree = REAPI.Tree.with {
            $0.root = directory
            $0.children = children.sorted { $0.key.hash < $1.key.hash }.map(\.value)
        }
        return try Snapshot(tree: persist(tree.serializedData()), blobs: blobs)
    }

    public static func fileDigests(in tree: REAPI.Tree) throws -> Set<REAPI.Digest> {
        var result = Set<REAPI.Digest>()
        for directory in [tree.root] + tree.children {
            for file in directory.files {
                try REAPI.validate(file.digest)
                result.insert(file.digest)
            }
        }
        return result
    }

    public static func materialize(
        _ tree: REAPI.Tree,
        at root: URL,
        fileSystem: FileSysteming = FileSystem(),
        blob: (REAPI.Digest) throws -> URL
    ) async throws {
        let manager = FileManager.default
        var directories: [REAPI.Digest: REAPI.Directory] = [:]
        for child in tree.children {
            directories[REAPI.digest(try child.serializedData())] = child
        }
        var count = 0
        var links: [URL] = []
        func visit(_ directory: REAPI.Directory, path: URL, depth: Int) async throws {
            guard depth < 128 else { throw REAPICacheError.invalidTree }
            let names = directory.files.map(\.name) + directory.directories.map(\.name) + directory.symlinks.map(\.name)
            count += names.count
            guard count <= 100_000, Set(names).count == names.count,
                  names.allSatisfy(validName)
            else { throw REAPICacheError.invalidTree }
            try await fileSystem.makeDirectory(at: AbsolutePath(validating: path.path))
            for file in directory.files {
                let destination = path.appendingPathComponent(file.name)
                try await fileSystem.copy(
                    AbsolutePath(validating: blob(file.digest).path),
                    to: AbsolutePath(validating: destination.path)
                )
                try manager.setAttributes([.posixPermissions: file.isExecutable ? 0o755 : 0o644], ofItemAtPath: destination.path)
            }
            for child in directory.directories {
                guard let contents = directories[child.digest] else { throw REAPICacheError.invalidTree }
                try await visit(contents, path: path.appendingPathComponent(child.name), depth: depth + 1)
            }
            for link in directory.symlinks {
                let destination = path.appendingPathComponent(link.name)
                try validateLink(link.target, at: destination, root: root)
                // FileSystem's RelativePath normalizes the target, changing chained-link semantics.
                try manager.createSymbolicLink(atPath: destination.path, withDestinationPath: link.target)
                links.append(destination)
            }
        }
        try await visit(tree.root, path: root, depth: 0)
        for link in links {
            try validateResolvedLink(link, root: root)
        }
    }

    public static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    private static func validateResolvedLink(_ path: URL, root: URL) throws {
        guard path.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw REAPICacheError.invalidTree
        }
    }

    private static func validateLink(_ target: String, at path: URL, root: URL) throws {
        let resolved = path.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL.path
        guard !target.hasPrefix("/"), !target.contains("\0"),
              resolved.hasPrefix(root.standardizedFileURL.path + "/")
        else { throw REAPICacheError.invalidTree }
    }
}
