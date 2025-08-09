import FileSystem
import Foundation
import Mockable
import Path
import TSCBasic
import TuistCore
import TuistSupport

@Mockable
public protocol XCConfigContentHashing {
    func hash(path: Path.AbsolutePath) async throws -> String
}

enum XCConfigContentHasherError: FatalError, Equatable {
    case recursiveIncludeInXCConfigDetected(path: Path.AbsolutePath, includedPath: Path.AbsolutePath)

    var description: String {
        switch self {
        case let .recursiveIncludeInXCConfigDetected(path, includedPath):
            return "Detected recursive include in XCConfig at path - `\(path)`. Included path - `\(includedPath)`"
        }
    }

    var type: ErrorType {
        switch self {
        case .recursiveIncludeInXCConfigDetected: return .abort
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

    private func hash(path: Path.AbsolutePath, processedPaths: Set<Path.AbsolutePath>) async throws -> String {
        let source = try await fileSystem.readTextFile(at: path)

        let pattern = "#include\\s*\"([^'\"]+)\""
        let includes = ((try? RegEx(pattern: pattern).matchGroups(in: source)) ?? []).joined()

        var xcconfigHash = try contentHasher.hash(source)

        for include in includes {
            let includePath = try Path.AbsolutePath(validating: include, relativeTo: path.parentDirectory)

            if processedPaths.contains(includePath) {
                throw XCConfigContentHasherError.recursiveIncludeInXCConfigDetected(path: path, includedPath: includePath)
            }

            let hash = try await hash(path: includePath, processedPaths: processedPaths.union([includePath]))
            xcconfigHash += hash
        }

        return xcconfigHash
    }
}
