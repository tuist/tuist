import Basic
import Foundation
import TuistSupport

enum XCFrameworkNodeLoaderError: FatalError {
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

final class XCFrameworkNodeLoader: XCFrameworkNodeLoading {
    /// xcframework metadata provider.
    fileprivate let xcframeworkMetadataProvider: XCFrameworkMetadataProviding

    /// Initializes the loader with its attributes.
    /// - Parameter xcframeworkMetadataProvider: xcframework metadata provider.
    init(xcframeworkMetadataProvider: XCFrameworkMetadataProviding = XCFrameworkMetadataProvider()) {
        self.xcframeworkMetadataProvider = xcframeworkMetadataProvider
    }

    func load(path: AbsolutePath) throws -> XCFrameworkNode {
        guard FileHandler.shared.exists(path) else {
            throw XCFrameworkNodeLoaderError.xcframeworkNotFound(path)
        }
        let infoPlist = try xcframeworkMetadataProvider.infoPlist(xcframeworkPath: path)
        let primaryBinaryPath = try xcframeworkMetadataProvider.binaryPath(xcframeworkPath: path,
                                                                           libraries: infoPlist.libraries)
        return XCFrameworkNode(path: path,
                               infoPlist: infoPlist,
                               primaryBinaryPath: primaryBinaryPath,
                               dependencies: [])
    }
}
