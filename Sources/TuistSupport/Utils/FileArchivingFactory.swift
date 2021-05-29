import TSCBasic

/// An interface that defines a factory of archiver and unarchivers.
public protocol FileArchivingFactorying {
    /// Returns an archiver to archive the given paths.
    /// - Parameter paths: Files to archive.
    func makeFileArchiver(for paths: [AbsolutePath]) throws -> FileArchiving

    /// Returns an unarchiver to unarchive the given zip file.
    /// - Parameter path: Path to the .zip file.
    func makeFileUnarchiver(for path: AbsolutePath) throws -> FileUnarchiving
}

public class FileArchivingFactory: FileArchivingFactorying {
    public init() {}

    public func makeFileArchiver(for paths: [AbsolutePath]) throws -> FileArchiving {
        try FileArchiver(paths: paths)
    }

    public func makeFileUnarchiver(for path: AbsolutePath) throws -> FileUnarchiving {
        try FileUnarchiver(path: path)
    }
}
