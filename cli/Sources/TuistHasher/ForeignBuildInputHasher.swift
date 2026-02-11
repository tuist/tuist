import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol ForeignBuildInputHashing {
    func hash(
        inputs: [ForeignBuildInput],
        hashedPaths: [AbsolutePath: String]
    ) async throws -> (hash: String, hashedPaths: [AbsolutePath: String])
}

public final class ForeignBuildInputHasher: ForeignBuildInputHashing {
    private let contentHasher: ContentHashing
    private let fileSystem: FileSysteming
    private let system: Systeming

    public init(
        contentHasher: ContentHashing,
        fileSystem: FileSysteming = FileSystem(),
        system: Systeming = System.shared
    ) {
        self.contentHasher = contentHasher
        self.fileSystem = fileSystem
        self.system = system
    }

    public func hash(
        inputs: [ForeignBuildInput],
        hashedPaths: [AbsolutePath: String]
    ) async throws -> (hash: String, hashedPaths: [AbsolutePath: String]) {
        var hashedPaths = hashedPaths
        var hashes: [String] = []

        for input in inputs {
            switch input {
            case let .file(path):
                let fileHash: String
                if let existing = hashedPaths[path] {
                    fileHash = existing
                } else {
                    fileHash = try await contentHasher.hash(path: path)
                    hashedPaths[path] = fileHash
                }
                hashes.append(fileHash)

            case let .folder(path):
                let folderHash = try await contentHasher.hash(path: path)
                hashedPaths[path] = folderHash
                hashes.append(folderHash)

            case let .glob(pattern):
                let directory: AbsolutePath
                let include: String
                if let lastSlash = pattern.lastIndex(of: "/"),
                   !pattern[pattern.startIndex ... lastSlash].contains("*")
                {
                    let dirString = String(pattern[pattern.startIndex ..< lastSlash])
                    directory = try AbsolutePath(validating: dirString)
                    include = String(pattern[pattern.index(after: lastSlash)...])
                } else {
                    directory = try AbsolutePath(validating: "/")
                    include = pattern
                }
                let matchedPaths = try await fileSystem.glob(directory: directory, include: [include]).collect().sorted()
                var globHashes: [String] = []
                for matchedPath in matchedPaths {
                    let matchedHash: String
                    if let existing = hashedPaths[matchedPath] {
                        matchedHash = existing
                    } else {
                        matchedHash = try await contentHasher.hash(path: matchedPath)
                        hashedPaths[matchedPath] = matchedHash
                    }
                    globHashes.append(matchedHash)
                }
                hashes.append(try contentHasher.hash(globHashes.joined()))

            case let .script(script):
                let output = try await system.runAndCollectOutput(["/bin/sh", "-c", script])
                hashes.append(try contentHasher.hash(output.standardOutput))
            }
        }

        let combinedHash = try contentHasher.hash(hashes.joined())
        return (hash: combinedHash, hashedPaths: hashedPaths)
    }
}
