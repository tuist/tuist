import Path

/// Generated Files Cleanup Descriptor
///
/// Describes a cleanup pass for generated files owned by Tuist.
///
/// - seealso: `SideEffectDescriptor`
public struct GeneratedFilesCleanupDescriptor: Equatable, CustomStringConvertible {
    /// Directories to clean.
    public var directories: Set<AbsolutePath>

    /// Files that are still active and should not be removed, keyed by their parent directory.
    public var activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>]

    /// Glob patterns that select the generated files owned by the cleanup pass.
    public var include: [String]

    /// Creates a Generated Files Cleanup Descriptor.
    /// - Parameters:
    ///   - directories: Directories to clean.
    ///   - activeFilesByDirectory: Files that are still active and should not be removed, keyed by their parent directory.
    ///   - include: Glob patterns that select the generated files owned by the cleanup pass.
    public init(
        directories: Set<AbsolutePath>,
        activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>],
        include: [String]
    ) {
        self.directories = directories
        self.activeFilesByDirectory = activeFilesByDirectory
        self.include = include
    }

    public var description: String {
        let directoriesDescription = directories
            .map(\.pathString)
            .sorted()
            .joined(separator: ", ")
        let includeDescription = include.joined(separator: ", ")
        return "cleanup generated files matching \(includeDescription) in \(directoriesDescription)"
    }
}
