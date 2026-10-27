import FileSystem
import Foundation
import Path

public enum CacheWarmScratchDirectory: Equatable, Sendable {
    case temporary
    case callerOwned(AbsolutePath)
}

public enum CacheWarmScratchDirectoryError: LocalizedError, Equatable {
    case notDirectory(AbsolutePath)
    case notEmpty(AbsolutePath)

    public var errorDescription: String? {
        switch self {
        case let .notDirectory(path):
            return "The cache warm scratch directory at \(path.pathString) is not a directory."
        case let .notEmpty(path):
            return "The cache warm scratch directory at \(path.pathString) must be empty."
        }
    }
}

public protocol CacheWarmScratchDirectoryPreparing {
    func prepare(path: AbsolutePath?) async throws -> CacheWarmScratchDirectory
}

public struct CacheWarmScratchDirectoryPreparer: CacheWarmScratchDirectoryPreparing {
    private let fileSystem: FileSysteming

    public init() {
        fileSystem = FileSystem()
    }

    init(fileSystem: FileSysteming) {
        self.fileSystem = fileSystem
    }

    public func prepare(path: AbsolutePath?) async throws -> CacheWarmScratchDirectory {
        guard let path else {
            return .temporary
        }

        guard try await fileSystem.exists(path) else {
            try await fileSystem.makeDirectory(at: path)
            return .callerOwned(path)
        }
        guard try await fileSystem.exists(path, isDirectory: true) else {
            throw CacheWarmScratchDirectoryError.notDirectory(path)
        }
        guard try await fileSystem.contentsOfDirectory(path).isEmpty else {
            throw CacheWarmScratchDirectoryError.notEmpty(path)
        }
        return .callerOwned(path)
    }
}
