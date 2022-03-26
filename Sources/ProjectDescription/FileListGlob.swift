import Foundation

/// A glob pattern that refers to files.
public struct FileListGlob: Codable, Equatable {
    /// The path with a glob pattern.
    public var glob: Path

    /// The excluding paths.
    public var excluding: [Path]

    /// Returns a generic file list glob.
    /// - Parameters:
    ///   - glob: The path with a glob pattern.
    ///   - excluding: The excluding paths.
    public static func glob(
        _ glob: Path,
        excluding: [Path] = []
    ) -> FileListGlob {
        FileListGlob(glob: glob, excluding: excluding)
    }

    /// Returns a file list glob with an optional excluding path.
    public static func glob(
        _ glob: Path,
        excluding: Path?
    ) -> FileListGlob {
        FileListGlob(
            glob: glob,
            excluding: excluding.flatMap { [$0] } ?? []
        )
    }
}

extension FileListGlob: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(glob: Path(value), excluding: [])
    }
}
