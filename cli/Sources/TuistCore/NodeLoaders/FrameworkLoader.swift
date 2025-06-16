import FileSystem
import Foundation
import Path
import TuistSupport
import XcodeGraph

enum FrameworkLoaderError: FatalError, Equatable {
    case frameworkNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .frameworkNotFound:
            return .abort
        }
    }

    /// Error description
    var description: String {
        switch self {
        case let .frameworkNotFound(path):
            return "Couldn't find framework at \(path.pathString)"
        }
    }
}

public protocol FrameworkLoading {
    /// Reads an existing framework and returns its in-memory representation, `GraphDependency.framework`.
    /// - Parameter path: Path to the .framework.
    /// - Parameter status: `.optional` to weakly link the .framework.
    func load(path: AbsolutePath, status: LinkingStatus) async throws -> GraphDependency
}

public final class FrameworkLoader: FrameworkLoading {
    /// Framework metadata provider.
    fileprivate let frameworkMetadataProvider: FrameworkMetadataProviding
    private let fileSystem: FileSysteming

    /// Initializes the loader with its attributes.
    /// - Parameter frameworkMetadataProvider: Framework metadata provider.
    public init(
        frameworkMetadataProvider: FrameworkMetadataProviding = FrameworkMetadataProvider(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.frameworkMetadataProvider = frameworkMetadataProvider
        self.fileSystem = fileSystem
    }

    public func load(path: AbsolutePath, status: LinkingStatus) async throws -> GraphDependency {
        guard try await fileSystem.exists(path) else {
            throw FrameworkLoaderError.frameworkNotFound(path)
        }

        let metadata = try await frameworkMetadataProvider.loadMetadata(
            at: path,
            status: status
        )

        return .framework(
            path: path,
            binaryPath: metadata.binaryPath,
            dsymPath: metadata.dsymPath,
            bcsymbolmapPaths: metadata.bcsymbolmapPaths,
            linking: metadata.linking,
            architectures: metadata.architectures,
            status: metadata.status
        )
    }
}

#if DEBUG
    public final class MockFrameworkLoader: FrameworkLoading {
        public init() {}

        var loadStub: ((AbsolutePath) throws -> GraphDependency)?
        public func load(path: AbsolutePath, status: LinkingStatus) throws -> GraphDependency {
            if let loadStub {
                return try loadStub(path)
            } else {
                return GraphDependency.testFramework(path: path, status: status)
            }
        }
    }

#endif
