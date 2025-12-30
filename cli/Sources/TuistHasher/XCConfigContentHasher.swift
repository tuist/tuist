import FileSystem
import Foundation
import Mockable
import OrderedSet
import Path
import struct TSCBasic.RegEx
import TuistCore
import TuistSupport

@Mockable
public protocol XCConfigContentHashing {
    func hash(path: Path.AbsolutePath) async throws -> String
}

enum XCConfigContentHasherError: LocalizedError, Equatable {
    case recursiveIncludeInXCConfigDetected(path: Path.AbsolutePath, includedPaths: [Path.AbsolutePath])

    var errorDescription: String? {
        switch self {
        case let .recursiveIncludeInXCConfigDetected(path, includedPaths):
            let includes = includedPaths.map { "`\($0.pathString)`" }.joined(separator: " -> ")
            return "The .xcconfig file at path `\(path.pathString)` includes itself recursively: \(includes)"
        }
    }
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
        try await hash(path: path, processedPaths: [path])
    }

    private func hash(
        path: Path.AbsolutePath,
        processedPaths: OrderedSet<Path.AbsolutePath>,
    ) async throws -> String {
        let source = try await fileSystem.readTextFile(at: path)

        let pattern = "#include\\s*\"([^'\"]+)\""
        let includes = ((try? RegEx(pattern: pattern).matchGroups(in: source)) ?? []).joined()

        var xcconfigHash = try contentHasher.hash(source)

        for include in includes {
            let includePath = try Path.AbsolutePath(validating: include, relativeTo: path.parentDirectory)

            if let index = processedPaths.firstIndex(of: includePath) {
                throw XCConfigContentHasherError.recursiveIncludeInXCConfigDetected(
                    path: includePath,
                    includedPaths: processedPaths[index...] + [includePath]
                )
            }

            let hash = try await hash(path: includePath, processedPaths: processedPaths.union(with: [includePath]))
            xcconfigHash += hash
        }

        return xcconfigHash
    }
}
