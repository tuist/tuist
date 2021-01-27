import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

enum LibraryDependencyLoaderError: FatalError, Equatable {
    case libraryNotFound(AbsolutePath)
    case publicHeadersNotFound(AbsolutePath)
    case swiftModuleMapNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .libraryNotFound: return .abort
        case .publicHeadersNotFound: return .abort
        case .swiftModuleMapNotFound: return .abort
        }
    }

    /// Error description
    var description: String {
        switch self {
        case let .libraryNotFound(path):
            return "The library \(path.pathString) does not exist."
        case let .publicHeadersNotFound(path):
            return "The public headers directory \(path.pathString) does not exist."
        case let .swiftModuleMapNotFound(path):
            return "The Swift modulemap file \(path.pathString) does not exist."
        }
    }
}

public protocol LibraryDependencyLoading {
    /// Reads an existing library and returns its in-memory representation, LibraryNode.
    /// - Parameters:
    ///   - path: Path to the library.
    ///   - publicHeaders: Path to the directorythat contains the public headers.
    ///   - swiftModuleMap: Path to the Swift modulemap file.
    func load(path: AbsolutePath,
              publicHeaders: AbsolutePath,
              swiftModuleMap: AbsolutePath?) throws -> ValueGraphDependency
}

final class LibraryDependencyLoader: LibraryDependencyLoading {
    /// Library metadata provider.
    fileprivate let libraryMetadataProvider: LibraryMetadataProviding

    /// Initializes the loader with its attributes.
    /// - Parameter libraryMetadataProvider: Library metadata provider.
    init(libraryMetadataProvider: LibraryMetadataProviding = LibraryMetadataProvider()) {
        self.libraryMetadataProvider = libraryMetadataProvider
    }

    func load(path: AbsolutePath,
              publicHeaders: AbsolutePath,
              swiftModuleMap: AbsolutePath?) throws -> ValueGraphDependency
    {
        if !FileHandler.shared.exists(path) {
            throw LibraryDependencyLoaderError.libraryNotFound(path)
        }
        if !FileHandler.shared.exists(publicHeaders) {
            throw LibraryDependencyLoaderError.publicHeadersNotFound(publicHeaders)
        }

        if let swiftModuleMap = swiftModuleMap {
            if !FileHandler.shared.exists(swiftModuleMap) {
                throw LibraryDependencyLoaderError.swiftModuleMapNotFound(swiftModuleMap)
            }
        }
        let architectures = try libraryMetadataProvider.architectures(binaryPath: path)
        let linking = try libraryMetadataProvider.linking(binaryPath: path)

        return .library(path: path,
                        publicHeaders: publicHeaders,
                        linking: linking,
                        architectures: architectures,
                        swiftModuleMap: swiftModuleMap)
    }
}
