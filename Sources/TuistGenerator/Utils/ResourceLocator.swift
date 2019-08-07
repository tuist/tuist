import Basic
import Foundation
import TuistCore

/// This protocol defines the interface to look up the path of tuist and its
/// components (frameworks) in the environment.
public protocol ResourceLocating: AnyObject {
    /// Returns the path to the ProjectDescription framework.
    ///
    /// - Returns: Path to the ProjectDescription framework.
    /// - Throws: An error if the path to the framework can't be obtained.
    func projectDescription() throws -> AbsolutePath

    /// Returns the path to the 'tuist' CLI binary.
    ///
    /// - Returns: The path to the tuist binary.
    /// - Throws: An error if the path can't be obtained.
    func cliPath() throws -> AbsolutePath
}

enum ResourceLocatingError: FatalError {
    /// Thrown when a resource can't be found.
    case notFound(String)

    /// Error description
    var description: String {
        switch self {
        case let .notFound(name):
            return "Couldn't find \(name)"
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        default:
            return .bug
        }
    }

    static func == (lhs: ResourceLocatingError, rhs: ResourceLocatingError) -> Bool {
        switch (lhs, rhs) {
        case let (.notFound(lhsPath), .notFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

public final class ResourceLocator: ResourceLocating {
    /// Instance to interact with the file system.
    private let fileHandler: FileHandling

    // MARK: - Init

    /// Initializes the resource locator.
    ///
    /// - Parameter fileHandler: Instance to interact with the file system.
    public init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    // MARK: - ResourceLocating

    /// Returns the path to the ProjectDescription framework.
    ///
    /// - Returns: Path to the ProjectDescription framework.
    /// - Throws: An error if the path to the framework can't be obtained.
    public func projectDescription() throws -> AbsolutePath {
        return try frameworkPath("ProjectDescription")
    }

    /// Returns the path to the 'tuist' CLI binary.
    ///
    /// - Returns: The path to the tuist binary.
    /// - Throws: An error if the path can't be obtained.
    public func cliPath() throws -> AbsolutePath {
        return try toolPath("tuist")
    }

    // MARK: - Fileprivate

    /// Looks up a tuist framework in the environment.
    ///
    /// - Parameter name: Binary to be looked up.
    /// - Returns: The path to the binary.
    /// - Throws: An error if the binary can't be found.
    private func frameworkPath(_ name: String) throws -> AbsolutePath {
        let frameworkNames = ["\(name).framework", "lib\(name).dylib"]
        let bundlePath = AbsolutePath(Bundle(for: ResourceLocator.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.flatMap { path in
            frameworkNames.map { path.appending(component: $0) }
        }
        guard let frameworkPath = candidates.first(where: { fileHandler.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return frameworkPath
    }

    /// Looks up a tuist binary in the environment.
    ///
    /// - Parameter name: Binary to be looked up.
    /// - Returns: The path to the binary.
    /// - Throws: An error if the binary can't be found.
    private func toolPath(_ name: String) throws -> AbsolutePath {
        let bundlePath = AbsolutePath(Bundle(for: ResourceLocator.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.map { $0.appending(component: name) }
        guard let path = candidates.first(where: { fileHandler.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return path
    }
}
