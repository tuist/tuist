import Darwin
import Foundation
import TSCBasic

let systemGlob = Darwin.glob

public enum GlobError: FatalError, Equatable {
    case nonExistentDirectory(InvalidGlob)

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .nonExistentDirectory(invalidGlob):
            return String(describing: invalidGlob)
        }
    }
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
        let globPath = appending(RelativePath(pattern)).pathString

        if globPath.isGlobComponent {
            let pathUpToLastNonGlob = AbsolutePath(globPath).upToLastNonGlob

            if !FileHandler.shared.isFolder(pathUpToLastNonGlob) {
                let invalidGlob = InvalidGlob(
                    pattern: globPath,
                    nonExistentPath: pathUpToLastNonGlob
                )
                throw GlobError.nonExistentDirectory(invalidGlob)
            }
        }

        return glob(pattern)
    }

    /// Returns true if the path is a package, recognized by having a UTI `com.apple.package`
    public var isPackage: Bool {
        let ext = URL(fileURLWithPath: pathString).pathExtension as CFString
        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, nil) else { return false }
        return UTTypeConformsTo(uti.takeRetainedValue(), kUTTypePackage)
    }

    private static let opaqueDirectoriesExtensions: Set<String> = [
        "xcassets",
        "scnassets",
        "xcdatamodeld",
        "docc",
        "playground",
        "bundle",
    ]

    /// An opaque directory is a directory that should be treated like a file, therefor ignoring its content.
    /// I.e.: .xcassets, .xcdatamodeld, etc...
    /// This property returns true when a file is contained in such directory.
    public var isInOpaqueDirectory: Bool {
        var currentDirectory = parentDirectory
        while currentDirectory != .root {
            if let `extension` = currentDirectory.extension,
               Self.opaqueDirectoriesExtensions.contains(`extension`)
            {
                return true
            }
            currentDirectory = currentDirectory.parentDirectory
        }
        return false
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
            if path.isDescendantOfOrEqual(to: nextPath) {
                ancestorPath = nextPath
            } else {
                break
            }
        }
        return ancestorPath
    }

    public var upToLastNonGlob: AbsolutePath {
        guard let index = components.firstIndex(where: { $0.isGlobComponent }) else {
            return self
        }

        return AbsolutePath(components[0 ..< index].joined(separator: "/"))
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
    var isGlobComponent: Bool {
        let globCharacters = CharacterSet(charactersIn: "*{}")
        return rangeOfCharacter(from: globCharacters) != nil
    }
}
