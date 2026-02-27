import Path

/// Represents a file inside a buildable folder, along with any compiler flags to apply to it.
public struct BuildableFolderFile: Sendable, Codable, Equatable, Hashable {
    /// The absolute path to the file within the buildable folder.
    public let path: AbsolutePath

    /// Compiler flags to apply when building this file. An empty string means no extra flags.
    public let compilerFlags: String?

    /// Initializes a buildable folder file.
    /// - Parameters:
    ///   - path: The absolute path to the file within the buildable folder.
    ///   - compilerFlags: Compiler flags to apply when building this file. An empty string means no extra flags.
    public init(path: AbsolutePath, compilerFlags: String?) {
        self.path = path
        self.compilerFlags = compilerFlags
    }
}

/// A buildable folder maps to a PBXFileSystemSynchronizedRootGroup in Xcode projects.
/// Synchronized groups were introduced in Xcode 16 to reduce git conflicts by having a reference
/// to a folder whose content is "synchronized" by Xcode itself. Think of it as Xcode resolving
/// the globs.
///
/// This struct describes a buildable folder, the exception rules for files within it, and the resolved file list.
public struct BuildableFolder: Sendable, Codable, Equatable, Hashable {
    /// The absolute path to the buildable folder.
    public var path: AbsolutePath

    /// Exceptions associated with this buildable folder, describing files to exclude or per-file build configuration overrides.
    public var exceptions: BuildableFolderExceptions

    /// The files resolved from this buildable folder, each with any per-file compiler flags.
    public var resolvedFiles: [BuildableFolderFile]

    /// Creates a new `BuildableFolder` instance.
    /// - Parameters:
    ///   - path: The absolute path to the buildable folder.
    ///   - exceptions: The set of exceptions (such as excluded files or custom compiler flags) for the folder.
    ///   - resolvedFiles: The list of files resolved from the folder, each file optionally having compiler flags.
    public init(path: AbsolutePath, exceptions: BuildableFolderExceptions, resolvedFiles: [BuildableFolderFile]) {
        self.path = path
        self.exceptions = exceptions
        self.resolvedFiles = resolvedFiles
    }
}
