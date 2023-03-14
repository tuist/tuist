import Darwin
import Foundation
import TSCBasic
import UniformTypeIdentifiers

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
        try! AbsolutePath(validating: FileManager.default.currentDirectoryPath) // swiftlint:disable:this force_try
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
        // swiftlint:disable:next force_try
        Glob(pattern: appending(RelativePath(pattern)).pathString).paths.map { try! AbsolutePath(validating: $0) }
    }

    /// Returns the list of paths that match the given glob pattern, if the directory exists.
    ///
    /// - Parameter pattern: Relative glob pattern used to match the paths.
    /// - Throws: an error if the directory where the first glob pattern is declared doesn't exist
    /// - Returns: List of paths that match the given pattern.
    public func throwingGlob(_ pattern: String) throws -> [AbsolutePath] {
        let globPath = appending(RelativePath(pattern)).pathString

        if globPath.isGlobComponent {
            let pathUpToLastNonGlob = try AbsolutePath(validating: globPath).upToLastNonGlob

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
        let ext = URL(fileURLWithPath: pathString).pathExtension
        guard let utType = UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil) else { return false }
        return utType.conforms(to: UTType.package)
    }

    /// An opaque directory is a directory that should be treated like a file, therefor ignoring its content.
    /// I.e.: .xcassets, .xcdatamodeld, etc...
    /// This property returns true when a file is contained in such directory.
    public var isInOpaqueDirectory: Bool {
        var currentDirectory = parentDirectory
        while currentDirectory != .root {
            if currentDirectory.isOpaqueDirectory { return true }
            currentDirectory = currentDirectory.parentDirectory
        }
        return false
    }

    /// An opaque directory is a directory that should be treated like a file, therefor ignoring its content.
    /// I.e.: .xcassets, .xcdatamodeld, etc...
    /// This property returns true when a file is such a directory.
    public var isOpaqueDirectory: Bool {
        [
            "xcassets",
            "scnassets",
            "xcdatamodeld",
            "docc",
            "playground",
            "bundle",
            "mlmodelc",
        ]
        .contains(self.extension ?? "")
    }

    /// Returns the path with the last component removed. For example, given the path
    /// /test/path/to/file it returns /test/path/to
    ///
    /// If the path is one-level deep from the root directory it returns the root directory.
    ///
    /// - Returns: Path with the last component removed.
    public func removingLastComponent() -> AbsolutePath {
        try! AbsolutePath(validating: "/\(components.dropLast().joined(separator: "/"))") // swiftlint:disable:this force_try
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
        var ancestorPath = try! AbsolutePath(validating: "/") // swiftlint:disable:this force_try
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

        return try! AbsolutePath(validating: components[0 ..< index].joined(separator: "/")) // swiftlint:disable:this force_try
    }

    /// Returns the hash of the file the path points to.
    public func sha256() -> Data? {
        try? SHA256Digest.file(at: url)
    }
}

extension AbsolutePath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = try! AbsolutePath(validating: value) // swiftlint:disable:this force_try
    }
}

extension String {
    var isGlobComponent: Bool {
        let globCharacters = CharacterSet(charactersIn: "*{}")
        return rangeOfCharacter(from: globCharacters) != nil
    }
}
