import Foundation
import Mockable
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

@Mockable
public protocol XCFrameworkLoading {
    /// Reads an existing xcframework and returns its in-memory representation, `GraphDependency.xcframework`.
    /// - Parameter path: Path to the .xcframework.
    /// - Parameter status: `.optional` to weakly reference the .xcframework.
    /// - Parameter isExternal: Whether the XCFramework comes from an external SPM project
    func load(path: AbsolutePath, status: FrameworkStatus, isExternal: Bool) throws -> GraphDependency
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

    public func load(path: AbsolutePath, status: FrameworkStatus, isExternal: Bool) throws -> GraphDependency {
        guard FileHandler.shared.exists(path) else {
            throw XCFrameworkLoaderError.xcframeworkNotFound(path)
        }
        let metadata = try xcframeworkMetadataProvider.loadMetadata(
            at: path,
            status: status
        )
        let xcframework = GraphDependency.XCFramework(
            path: path,
            infoPlist: metadata.infoPlist,
            primaryBinaryPath: metadata.primaryBinaryPath,
            linking: metadata.linking,
            mergeable: metadata.mergeable,
            status: metadata.status,
            isExternal: isExternal
        )
        return .xcframework(xcframework)
    }
}
