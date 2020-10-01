import Foundation
import TSCBasic
import TuistSupport

public protocol FrameworkMetadataProviding: PrecompiledMetadataProviding {
    /// Given the path to a framework, it returns the path to its dSYMs if they exist
    /// in the same framework directory.
    /// - Parameter frameworkPath: Path to the .framework directory.
    func dsymPath(frameworkPath: AbsolutePath) -> AbsolutePath?

    /// Given the path to a framework, it returns the list of .bcsymbolmap files that
    /// are associated to the framework and that are present in the same directory.
    /// - Parameter frameworkPath: Path to the .framework directory.
    func bcsymbolmapPaths(frameworkPath: AbsolutePath) throws -> [AbsolutePath]

    /// Returns the product for the framework at the given path.
    /// - Parameter frameworkPath: Path to the .framework directory.
    func product(frameworkPath: AbsolutePath) throws -> Product
}

public final class FrameworkMetadataProvider: PrecompiledMetadataProvider, FrameworkMetadataProviding {
    public func dsymPath(frameworkPath: AbsolutePath) -> AbsolutePath? {
        let path = AbsolutePath("\(frameworkPath.pathString).dSYM")
        if FileHandler.shared.exists(path) { return path }
        return nil
    }

    public func bcsymbolmapPaths(frameworkPath: AbsolutePath) throws -> [AbsolutePath] {
        let binaryPath = FrameworkNode.binaryPath(frameworkPath: frameworkPath)
        let uuids = try self.uuids(binaryPath: binaryPath)
        return uuids
            .map { frameworkPath.parentDirectory.appending(component: "\($0).bcsymbolmap") }
            .filter { FileHandler.shared.exists($0) }
            .sorted()
    }

    public func product(frameworkPath: AbsolutePath) throws -> Product {
        let binaryPath = FrameworkNode.binaryPath(frameworkPath: frameworkPath)
        switch try linking(binaryPath: binaryPath) {
        case .dynamic:
            return .framework
        case .static:
            return .staticFramework
        }
    }
}
