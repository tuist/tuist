import Foundation

/// It represents a list of glob patterns that refer to files.
/// The list of files can be initialized with a string that represents the glob pattern, or an array of strings, which represents a list of glob patterns.
public struct FileList: Codable, Equatable {
    /// Glob pattern to the files.
    public let globs: [FileListGlob]

    /// Initializes the files list with the glob patterns.
    ///
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    public static func list(_ globs: [FileListGlob]) -> FileList {
        .init(globs)
    }

    /// Initializes the files list with the glob patterns.
    ///
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    private init(_ globs: [FileListGlob]) {
        self.globs = globs
    }
}

extension FileList: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init([.init(stringLiteral: value)])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(elements.map { .init(stringLiteral: $0) })
    }
}
