import Foundation

/// A path represents to a file, directory, or a group of files represented by a glob expression.
///
/// Paths can be relative and absolute. We discourage using absolute paths because they create a dependency with the environment
/// where they are defined.
public struct Path: ExpressibleByStringInterpolation, Codable, Hashable, Sendable {
    public enum PathType: String, Codable, Sendable {
        case relativeToCurrentFile
        case relativeToManifest
        case relativeToRoot
    }

    public var type: PathType
    public var pathString: String
    public var callerPath: String?

    /// Default PathType is `.relativeToManifest`
    public static func path(_ path: String) -> Self {
        self.init(path, type: .relativeToManifest)
    }

    init(
        _ pathString: String,
        type: PathType,
        callerPath: String? = nil
    ) {
        self.type = type
        self.pathString = pathString
        self.callerPath = callerPath
    }

    /// Initialize a path that is relative to the file that defines the path.
    public static func relativeToCurrentFile(_ pathString: String, callerPath: StaticString = #file) -> Path {
        Path(pathString, type: .relativeToCurrentFile, callerPath: "\(callerPath)")
    }

    /// Initialize a path that is relative to the directory that contains the manifest file being loaded, for example the
    /// directory that contains the Project.swift file.
    public static func relativeToManifest(_ pathString: String) -> Path {
        Path(pathString, type: .relativeToManifest)
    }

    /// Initialize a path that is relative to the closest directory that contains a Tuist or a .git directory.
    public static func relativeToRoot(_ pathString: String) -> Path {
        Path(pathString, type: .relativeToRoot)
    }

    // MARK: - ExpressibleByStringInterpolation

    /// Initializer uses `.relativeToRoot` if path starts with `//` otherwise it is `.relativeToManifest` by default
    public init(stringLiteral: String) {
        if stringLiteral.starts(with: "//") {
            self.init(stringLiteral.replacingOccurrences(of: "//", with: ""), type: .relativeToRoot)
        } else {
            self.init(stringLiteral, type: .relativeToManifest)
        }
    }
}
