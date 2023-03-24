import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

// MARK: - Provider Errors

enum FrameworkMetadataProviderError: FatalError, Equatable {
    case frameworkNotFound(AbsolutePath)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .frameworkNotFound(path):
            return "Couldn't find framework at \(path.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .frameworkNotFound:
            return .abort
        }
    }
}

// MARK: - Provider

public protocol FrameworkMetadataProviding: PrecompiledMetadataProviding {
    /// Loads all the metadata associated with a framework at the specified path
    /// - Note: This performs various shell calls and disk operations
    func loadMetadata(at path: AbsolutePath) throws -> FrameworkMetadata

    /// Given the path to a framework, it returns the path to its dSYMs if they exist
    /// in the same framework directory.
    /// - Parameter frameworkPath: Path to the .framework directory.
    func dsymPath(frameworkPath: AbsolutePath) throws -> AbsolutePath?

    /// Given the path to a framework, it returns the list of .bcsymbolmap files that
    /// are associated to the framework and that are present in the same directory.
    /// - Parameter frameworkPath: Path to the .framework directory.
    func bcsymbolmapPaths(frameworkPath: AbsolutePath) throws -> [AbsolutePath]

    /// Returns the product for the framework at the given path.
    /// - Parameter frameworkPath: Path to the .framework directory.
    func product(frameworkPath: AbsolutePath) throws -> Product
}

// MARK: - Default Implementation

public final class FrameworkMetadataProvider: PrecompiledMetadataProvider, FrameworkMetadataProviding {
    override public init() {
        super.init()
    }

    public func loadMetadata(at path: AbsolutePath) throws -> FrameworkMetadata {
        let fileHandler = FileHandler.shared
        guard fileHandler.exists(path) else {
            throw FrameworkMetadataProviderError.frameworkNotFound(path)
        }
        let binaryPath = binaryPath(frameworkPath: path)
        let dsymPath = try dsymPath(frameworkPath: path)
        let bcsymbolmapPaths = try bcsymbolmapPaths(frameworkPath: path)
        let linking = try linking(binaryPath: binaryPath)
        let architectures = try architectures(binaryPath: binaryPath)
        let isCarthage = path.pathString.contains("Carthage/Build")
        return FrameworkMetadata(
            path: path,
            binaryPath: binaryPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            isCarthage: isCarthage
        )
    }

    public func dsymPath(frameworkPath: AbsolutePath) throws -> AbsolutePath? {
        let path = try AbsolutePath(validating: "\(frameworkPath.pathString).dSYM")
        if FileHandler.shared.exists(path) { return path }
        return nil
    }

    public func bcsymbolmapPaths(frameworkPath: AbsolutePath) throws -> [AbsolutePath] {
        let binaryPath = binaryPath(frameworkPath: frameworkPath)
        let uuids = try uuids(binaryPath: binaryPath)
        return uuids
            .map { frameworkPath.parentDirectory.appending(component: "\($0).bcsymbolmap") }
            .filter { FileHandler.shared.exists($0) }
            .sorted()
    }

    public func product(frameworkPath: AbsolutePath) throws -> Product {
        let binaryPath = binaryPath(frameworkPath: frameworkPath)
        switch try linking(binaryPath: binaryPath) {
        case .dynamic:
            return .framework
        case .static:
            return .staticFramework
        }
    }

    private func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        frameworkPath.appending(component: frameworkPath.basenameWithoutExt)
    }
}
