import Foundation
import TSCBasic
import TuistSupport

enum XCFrameworkNodeLoaderError: FatalError, Equatable {
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

public protocol XCFrameworkNodeLoading {
    /// Reads an existing xcframework and returns its in-memory representation, XCFrameworkNode..
    /// - Parameter path: Path to the .xcframework.
    func load(path: AbsolutePath) throws -> XCFrameworkNode
}

public final class XCFrameworkNodeLoader: XCFrameworkNodeLoading {
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

    public func load(path: AbsolutePath) throws -> XCFrameworkNode {
        guard FileHandler.shared.exists(path) else {
            throw XCFrameworkNodeLoaderError.xcframeworkNotFound(path)
        }
        let infoPlist = try xcframeworkMetadataProvider.infoPlist(xcframeworkPath: path)
        let primaryBinaryPath = try xcframeworkMetadataProvider.binaryPath(
            xcframeworkPath: path,
            libraries: infoPlist.libraries
        )
        let linking = try xcframeworkMetadataProvider.linking(binaryPath: primaryBinaryPath)
        return XCFrameworkNode(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            linking: linking,
            dependencies: []
        )
    }
}
