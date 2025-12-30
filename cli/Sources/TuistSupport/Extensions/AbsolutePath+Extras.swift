import Darwin
import Foundation
import Path
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

    /// Returns true if the path is a package, recognized by having a UTI `com.apple.package`
    public var isPackage: Bool {
        let ext = URL(fileURLWithPath: pathString).pathExtension
        guard let utType = UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil) else { return false }
        return utType.conforms(to: UTType.package)
    }

    /// An opaque directory is a directory that should be treated like a file, therefore ignoring its content.
    /// I.e.: .xcassets, .xcdatamodeld, etc...
    /// This property returns true when a file is contained in such directory.
    public var isInOpaqueDirectory: Bool {
        opaqueParentDirectory() != nil
    }

    /// An opaque directory is a directory that should be treated like a file, therefore ignoring its content.
    /// I.e.: .xcassets, .xcdatamodeld, etc...
    /// This property returns the first such parent directory if it exists. It returns `nil` otherwise.
    public func opaqueParentDirectory() -> AbsolutePath? {
        var currentDirectory = parentDirectory
        while currentDirectory != .root {
            if currentDirectory.isOpaqueDirectory { return currentDirectory }
            currentDirectory = currentDirectory.parentDirectory
        }
        return nil
    }

    /// An opaque directory is a directory that should be treated like a file, therefor ignoring its content.
    /// I.e.: .xcassets, .xcdatamodeld, etc...
    /// This property returns true when a file is such a directory.
    public var isOpaqueDirectory: Bool {
        [
            "xcassets",
            "scnassets",
            "xcdatamodel",
            "xcdatamodeld",
            "docc",
            "playground",
            "bundle",
            "mlmodelc",
            "xcmappingmodel",
            "icon",
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

extension AbsolutePath: Swift.ExpressibleByStringLiteral {
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

extension AbsolutePath {
    /// `true` if the path is of a glob pattern, `no` otherwise.
    public var isGlobPath: Bool {
        return pathString.isGlobComponent
    }
}
