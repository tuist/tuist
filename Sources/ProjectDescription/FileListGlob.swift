import Foundation

/// A glob pattern that refers to files.
public struct FileListGlob: Codable, Equatable {
    /// The path with a glob pattern.
    public var glob: Path

    /// The excluding paths.
    public var excluding: [Path] = []
}

extension FileListGlob: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(glob: Path(value), excluding: [])
    }
}
