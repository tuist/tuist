import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

enum XCFrameworkLoaderError: FatalError, Equatable {
    case xcframeworkNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .xcframeworkNotFound:
            return .abort
        }
    }

    /// Error description
    var description: String {
        switch self {
        case let .xcframeworkNotFound(path):
            return "Couldn't find xcframework at \(path.pathString)"
        }
    }
}

public protocol XCFrameworkLoading {
    /// Reads an existing xcframework and returns its in-memory representation, `GraphDependency.xcframework`.
    /// - Parameter path: Path to the .xcframework.
    func load(path: AbsolutePath) throws -> GraphDependency
}

public final class XCFrameworkLoader: XCFrameworkLoading {
    /// xcframework metadata provider.
    fileprivate let xcframeworkMetadataProvider: XCFrameworkMetadataProviding

    public convenience init() {
        self.init(xcframeworkMetadataProvider: XCFrameworkMetadataProvider())
    }

    /// Initializes the loader with its attributes.
    /// - Parameter xcframeworkMetadataProvider: xcframework metadata provider.
    init(xcframeworkMetadataProvider: XCFrameworkMetadataProviding) {
        self.xcframeworkMetadataProvider = xcframeworkMetadataProvider
    }

    public func load(path: AbsolutePath) throws -> GraphDependency {
        guard FileHandler.shared.exists(path) else {
            throw XCFrameworkLoaderError.xcframeworkNotFound(path)
        }
        let metadata = try xcframeworkMetadataProvider.loadMetadata(at: path)
        return .xcframework(
            path: path,
            infoPlist: metadata.infoPlist,
            primaryBinaryPath: metadata.primaryBinaryPath,
            linking: metadata.linking
        )
    }
}
