import Darwin
import Foundation
import TSCBasic

let systemGlob = Darwin.glob

enum GlobError: Error {
    case inexistentDirectory
}

extension AbsolutePath {
    /// Returns the current path.
    public static var current: AbsolutePath {
        AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    /// Returns the URL that references the absolute path.
    public var url: URL {
        URL(fileURLWithPath: pathString)
    }

    /// Returns the list of paths that match the given glob pattern.
    ///
    /// - Parameter pattern: Relative glob pattern used to match the paths.
    /// - Returns: List of paths that match the given pattern.
    public func glob(_ pattern: String) -> [AbsolutePath] {
        Glob(pattern: appending(RelativePath(pattern)).pathString).paths.map { AbsolutePath($0) }
    }

    /// Returns the list of paths that match the given glob pattern, if the directory exists.
    ///
    /// - Parameter pattern: Relative glob pattern used to match the paths.
    /// - Throws: an error if the directory where the first glob pattern is declared doesn't exist
    /// - Returns: List of paths that match the given pattern.
    public func throwingGlob(_ pattern: String) throws -> [AbsolutePath] {
        let path = appending(RelativePath(pattern)).pathString
        let pathUpToLastNonGlob = path.pathUpToLastNonGlob

        if !FileHandler.shared.isFolder(.init(pathUpToLastNonGlob)) {
            throw GlobError.inexistentDirectory
        }

        return glob(pattern)
    }

    /// Returns the path with the last component removed. For example, given the path
    /// /test/path/to/file it returns /test/path/to
    ///
    /// If the path is one-level deep from the root directory it returns the root directory.
    ///
    /// - Returns: Path with the last component removed.
    public func removingLastComponent() -> AbsolutePath {
        AbsolutePath("/\(components.dropLast().joined(separator: "/"))")
    }

    /// Returns the common ancestor path with another path
    ///
    /// e.g.
    ///     /path/to/a
    ///     /path/another/b
    ///
    ///     common ancestor: /path
    ///
    /// - Parameter path: The other path to find a common path with
    /// - Returns: An absolute path to the common ancestor
    public func commonAncestor(with path: AbsolutePath) -> AbsolutePath {
        var ancestorPath = AbsolutePath("/")
        for component in components.dropFirst() {
            let nextPath = ancestorPath.appending(component: component)
            if path.contains(nextPath) {
                ancestorPath = nextPath
            } else {
                break
            }
        }
        return ancestorPath
    }

    /// Returns the hash of the file the path points to.
    public func sha256() -> Data? {
        try? SHA256Digest.file(at: url)
    }
}

extension AbsolutePath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = AbsolutePath(value)
    }
}

extension String {
    private var isGlobComponent: Bool {
        self == "**" || self == "*" || hasPrefix("*.")
    }

    var pathUpToLastNonGlob: String {
        let pathComponents = components(separatedBy: "/")
        if let index = pathComponents.firstIndex(where: { $0.isGlobComponent }) {
            return pathComponents[0..<index].joined(separator: "/")
        }

        return self
    }
}
