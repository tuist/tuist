import Foundation
import TSCBasic
import TuistSupport

enum FrameworkNodeLoaderError: FatalError, Equatable {
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

public protocol FrameworkNodeLoading {
    /// Reads an existing framework and returns its in-memory representation, FrameworkNode.
    /// - Parameter path: Path to the .framework.
    func load(path: AbsolutePath) throws -> FrameworkNode
}

public final class FrameworkNodeLoader: FrameworkNodeLoading {
    /// Framework metadata provider.
    fileprivate let frameworkMetadataProvider: FrameworkMetadataProviding

    /// Initializes the loader with its attributes.
    /// - Parameter frameworkMetadataProvider: Framework metadata provider.
    public init(frameworkMetadataProvider: FrameworkMetadataProviding = FrameworkMetadataProvider()) {
        self.frameworkMetadataProvider = frameworkMetadataProvider
    }

    public func load(path: AbsolutePath) throws -> FrameworkNode {
        guard FileHandler.shared.exists(path) else {
            throw FrameworkNodeLoaderError.frameworkNotFound(path)
        }

        let binaryPath = FrameworkNode.binaryPath(frameworkPath: path)
        let dsymsPath = frameworkMetadataProvider.dsymPath(frameworkPath: path)
        let bcsymbolmapPaths = try frameworkMetadataProvider.bcsymbolmapPaths(frameworkPath: path)
        let linking = try frameworkMetadataProvider.linking(binaryPath: binaryPath)
        let architectures = try frameworkMetadataProvider.architectures(binaryPath: binaryPath)

        return FrameworkNode(
            path: path,
            dsymPath: dsymsPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures
        )
    }
}
