import FileSystem
import Foundation
import Mockable
import Path
import TSCBasic
import TuistCore

@Mockable
public protocol XCConfigContentHashing {
    func hash(path: Path.AbsolutePath) async throws -> String
}

/// `XCConfigContentHasher`
/// is responsible for computing a hash that uniquely identifies some `xcconfig` file
public struct XCConfigContentHasher: XCConfigContentHashing {
    private let contentHasher: ContentHashing
    private let fileSystem: FileSysteming

    // MARK: - Init

    public init(contentHasher: ContentHashing, fileSystem: FileSysteming = FileSystem()) {
        self.contentHasher = contentHasher
        self.fileSystem = fileSystem
    }

    // MARK: - XCConfigContentHashing

    public func hash(path: Path.AbsolutePath) async throws -> String {
        let source = try await fileSystem.readTextFile(at: path)

        let pattern = "#include\\s*\"([^'\"]+)\""
        let includes = ((try? RegEx(pattern: pattern).matchGroups(in: source)) ?? []).joined()

        var xcconfigHash = try contentHasher.hash(source)

        for include in includes {
            let includePath = try Path.AbsolutePath(validating: include, relativeTo: path.parentDirectory)
            let hash = try await hash(path: includePath)
            xcconfigHash += hash
        }

        return xcconfigHash
    }
}
