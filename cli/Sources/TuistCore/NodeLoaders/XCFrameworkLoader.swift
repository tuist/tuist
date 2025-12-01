import FileSystem
import Foundation
import Path
import TuistSupport
import XcodeGraph
import XcodeMetadata

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
    /// - Parameter expectedSignature: expected signature if the xcframework is signed, `nil` otherwise.
    /// - Parameter status: `.optional` to weakly reference the .xcframework.
    func load(path: AbsolutePath, expectedSignature: XCFrameworkSignature?, status: LinkingStatus)
        async throws -> GraphDependency
}

public final class XCFrameworkLoader: XCFrameworkLoading {
    /// xcframework metadata provider.
    fileprivate let xcframeworkMetadataProvider: XCFrameworkMetadataProviding
    private let fileSystem: FileSysteming

    public convenience init() {
        self.init(xcframeworkMetadataProvider: XCFrameworkMetadataProvider(logger: Logger.current))
    }

    /// Initializes the loader with its attributes.
    /// - Parameter xcframeworkMetadataProvider: xcframework metadata provider.
    init(
        xcframeworkMetadataProvider: XCFrameworkMetadataProviding,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.xcframeworkMetadataProvider = xcframeworkMetadataProvider
        self.fileSystem = fileSystem
    }

    public func load(
        path: AbsolutePath,
        expectedSignature: XCFrameworkSignature?,
        status: LinkingStatus
    ) async throws -> GraphDependency {
        guard try await fileSystem.exists(path) else {
            throw XCFrameworkLoaderError.xcframeworkNotFound(path)
        }
        let metadata = try await xcframeworkMetadataProvider.loadMetadata(
            at: path,
            expectedSignature: expectedSignature,
            status: status
        )
        let xcframework = GraphDependency.XCFramework(
            path: path,
            infoPlist: metadata.infoPlist,
            linking: metadata.linking,
            mergeable: metadata.mergeable,
            status: metadata.status,
            swiftModules: metadata.swiftModules,
            moduleMaps: metadata.moduleMaps,
            expectedSignature: metadata.expectedSignature?.signatureString()
        )
        return .xcframework(xcframework)
    }
}

#if DEBUG
    public final class MockXCFrameworkLoader: XCFrameworkLoading {
        public init() {}

        var loadStub: ((AbsolutePath) throws -> GraphDependency)?
        public func load(
            path: Path.AbsolutePath,
            expectedSignature _: XcodeGraph.XCFrameworkSignature?,
            status: XcodeGraph.LinkingStatus
        ) throws -> GraphDependency {
            if let loadStub {
                return try loadStub(path)
            } else {
                return .testXCFramework(path: path, status: status)
            }
        }
    }
#endif
