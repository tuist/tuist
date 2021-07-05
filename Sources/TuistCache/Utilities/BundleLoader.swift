import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

enum BundleLoaderError: FatalError, Equatable {
    case bundleNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .bundleNotFound:
            return .abort
        }
    }

    /// Error description
    var description: String {
        switch self {
        case let .bundleNotFound(path):
            return "Couldn't find bundle at \(path.pathString)"
        }
    }
}

public protocol BundleLoading {
    /// Reads an existing bundle and returns its in-memory representation, `ValueGraphDependency.bundle`.
    /// - Parameter path: Path to the .bundle.
    func load(path: AbsolutePath) throws -> GraphDependency
}

public final class BundleLoader: BundleLoading {
    /// Initializes the loader with its attributes.
    public init() {}

    public func load(path: AbsolutePath) throws -> GraphDependency {
        guard FileHandler.shared.exists(path) else {
            throw BundleLoaderError.bundleNotFound(path)
        }

        return .bundle(path: path)
    }
}
