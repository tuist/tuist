import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

enum FrameworkDependencyLoaderError: FatalError, Equatable {
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
            return "Couldn't find framework at \(path.pathString)."
        }
    }
}

public protocol FrameworkDependencyLoading {
    /// Reads an existing framework and returns its in-memory representation, FrameworkNode.
    /// - Parameter path: Path to the .framework.
    func load(path: AbsolutePath) throws -> ValueGraphDependency
}

public final class FrameworkDependencyLoader: FrameworkDependencyLoading {
    /// Framework metadata provider.
    fileprivate let frameworkMetadataProvider: FrameworkMetadataProviding

    /// Initializes the loader with its attributes.
    /// - Parameter frameworkMetadataProvider: Framework metadata provider.
    public init(frameworkMetadataProvider: FrameworkMetadataProviding = FrameworkMetadataProvider()) {
        self.frameworkMetadataProvider = frameworkMetadataProvider
    }

    public func load(path: AbsolutePath) throws -> ValueGraphDependency {
        guard FileHandler.shared.exists(path) else {
            throw FrameworkDependencyLoaderError.frameworkNotFound(path)
        }

        let frameworkName = path.basename.replacingOccurrences(of: ".framework", with: "")
        let binaryPath = path.appending(component: frameworkName)
        let dsymsPath = frameworkMetadataProvider.dsymPath(frameworkPath: path)
        let bcsymbolmapPaths = try frameworkMetadataProvider.bcsymbolmapPaths(frameworkPath: path)
        let linking = try frameworkMetadataProvider.linking(binaryPath: binaryPath)
        let architectures = try frameworkMetadataProvider.architectures(binaryPath: binaryPath)

        return ValueGraphDependency.framework(path: path,
                                              binaryPath: binaryPath,
                                              dsymPath: dsymsPath,
                                              bcsymbolmapPaths: bcsymbolmapPaths,
                                              linking: linking,
                                              architectures: architectures,
                                              isCarthage: path.pathString.contains("Carthage/Build"))
    }
}
