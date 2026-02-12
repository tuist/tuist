import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol ForeignBuildHashing {
    func hash(
        inputs: [ForeignBuildInput],
        hashedPaths: [AbsolutePath: String]
    ) async throws -> (hash: String, hashedPaths: [AbsolutePath: String])
}

public struct ForeignBuildHasher: ForeignBuildHashing {
    private let contentHasher: ContentHashing
    private let system: Systeming

    public init(
        contentHasher: ContentHashing,
        system: Systeming = System.shared
    ) {
        self.contentHasher = contentHasher
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
                let folderHash: String
                if let existing = hashedPaths[path] {
                    folderHash = existing
                } else {
                    folderHash = try await contentHasher.hash(path: path)
                    hashedPaths[path] = folderHash
                }
                hashes.append(folderHash)

            case let .script(script):
                let output = try await system.runAndCollectOutput(["/bin/sh", "-c", script])
                hashes.append(try contentHasher.hash(output.standardOutput))
            }
        }

        let combinedHash = try contentHasher.hash(hashes.joined())
        return (hash: combinedHash, hashedPaths: hashedPaths)
    }
}
