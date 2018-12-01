import Basic
import Darwin
import Foundation

let systemGlob = Darwin.glob

extension AbsolutePath {
    /// Returns the current path.
    public static var current: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    /// Returns the URL that references the absolute path.
    public var url: URL {
        return URL(fileURLWithPath: asString)
    }

    /// Returns the list of paths that match the given glob pattern.
    ///
    /// - Parameter pattern: Relative glob pattern used to match the paths.
    /// - Returns: List of paths that match the given pattern.
    public func glob(_ pattern: String) -> [AbsolutePath] {
        return Glob(pattern: appending(RelativePath(pattern)).asString).paths.map({ AbsolutePath($0) })
    }

    /// Returns the path with the last component removed. For example, given the path
    /// /test/path/to/file it returns /test/path/to
    ///
    /// If the path is one-level deep from the root directory it returns the root directory.
    ///
    /// - Returns: Path with the last component removed.
    public func removingLastComponent() -> AbsolutePath {
        return AbsolutePath("/\(components.dropLast().joined(separator: "/"))")
    }

    /// Returns a function to sorten files for Xcode projects.
    /// - Returns: Sortening function.
    public static func xcodeSortener() -> ((AbsolutePath, AbsolutePath) -> Bool) {
        return { lhs, rhs in
            lhs.components.count < rhs.components.count || lhs.asString < rhs.asString
        }
    }
}
