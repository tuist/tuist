import Foundation

/// A collection of file globs.
///
/// The list of files can be initialized with a string that represents the glob pattern, or an array of strings, which represents a list of glob patterns.
public struct FileList: Codable, Equatable {
    /// Glob pattern to the files.
    public let globs: [FileListGlob]

    /// Creates a file list from a collection of glob patterns.
    ///
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    public static func list(_ globs: [FileListGlob]) -> FileList {
        FileList(globs: globs)
    }
}

extension FileList: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(globs: [.init(stringLiteral: value)])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(globs: elements.map { .init(stringLiteral: $0) })
    }
}
