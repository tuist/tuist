import Darwin
import Foundation
import TSCBasic

let systemGlob = Darwin.glob

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

    public func md5() throws -> String {
        try Data(contentsOf: url).md5
    }
    
    public func base64MD5() throws -> String {
        guard let utf8str = try self.md5().data(using: .utf8) else { throw "Can't convert md5 into Data" }
        return utf8str.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }
}

extension AbsolutePath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = AbsolutePath(value)
    }
}
