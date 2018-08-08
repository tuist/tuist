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

    public func glob(_ pattern: String) -> [AbsolutePath] {
        return Glob(pattern: appending(RelativePath(pattern)).asString).paths.map({ AbsolutePath($0) })
    }

    public func removingLastComponent() -> AbsolutePath {
        return AbsolutePath("/\(components.dropLast().joined(separator: "/"))")
    }
}
