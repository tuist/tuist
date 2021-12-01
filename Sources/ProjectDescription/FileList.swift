import Foundation

public struct FileList: Codable, Equatable {
    /// List glob patterns.
    public let globs: [Path]

    /// Relative glob patterns for excluded files.
    public let excluding: [Path]

    /// Initializes the files list with the glob patterns.
    ///
    ///   - glob: Relative glob pattern.
    ///   - excluding: Relative glob patterns for excluded files.
    public init(globs: [Path],
                excluding: [Path]? = nil) {
        self.globs = globs
        self.excluding = excluding ?? []
    }

    public static func == (lhs: FileList, rhs: FileList) -> Bool {
        lhs.globs == rhs.globs && lhs.excluding == rhs.globs
    }
}

extension FileList: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(globs: [Path(value)])
    }
}

extension FileList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(globs: elements.map { Path($0) })
    }
}
